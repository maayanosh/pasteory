import Foundation
import Combine

@MainActor
public final class Store: ObservableObject {
    @Published public private(set) var items: [ClipItem] = []
    @Published public private(set) var pinboards: [Pinboard] = []

    public var historyLimit: Int = 500 {
        didSet { enforceLimit(); scheduleSave() }
    }

    public let directory: URL
    public var contentDir: URL { directory.appendingPathComponent("content") }
    private var storeFile: URL { directory.appendingPathComponent("store.json") }
    private var saveWorkItem: DispatchWorkItem?
    /// Serial queue for disk work (saves, orphan sweeps) so writes stay
    /// ordered without blocking the main thread.
    private let diskQueue = DispatchQueue(label: "com.local.pasteclone.store-disk", qos: .utility)

    struct Snapshot: Codable, Sendable {
        static let currentVersion = 1

        var version: Int
        var items: [ClipItem]
        var pinboards: [Pinboard]

        init(items: [ClipItem], pinboards: [Pinboard]) {
            self.version = Self.currentVersion
            self.items = items
            self.pinboards = pinboards
        }

        enum CodingKeys: String, CodingKey { case version, items, pinboards }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Files written before the version field existed decode as v1.
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            items = try c.decode([ClipItem].self, forKey: .items)
            pinboards = try c.decode([Pinboard].self, forKey: .pinboards)
        }
    }

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PasteClone")
        let fm = FileManager.default
        // Clipboard history is sensitive; keep the data directory owner-only.
        // setAttributes also tightens directories created by older builds.
        try? fm.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.createDirectory(at: contentDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
        load()
        collectOrphanedContentFiles()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeFile) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            items = snapshot.items
            pinboards = snapshot.pinboards
        } catch {
            // Unreadable store: set it aside (timestamped, so a second
            // corruption doesn't destroy the first backup) rather than let
            // the next save overwrite data the user might want to recover.
            NSLog("Clap: store.json unreadable, moving aside: \(error)")
            let backup = directory.appendingPathComponent(
                "store.json.corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: storeFile, to: backup)
        }
    }

    /// Snapshots the current state and writes it out on the disk queue.
    /// Non-blocking; call `flush()` to wait for the bytes to land.
    public func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let snapshot = Snapshot(items: items, pinboards: pinboards)
        let url = storeFile
        diskQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("Clap: store save failed: \(error)")
            }
        }
    }

    /// Blocks until every queued save has hit the disk. Call before exit.
    public func flush() {
        diskQueue.sync {}
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Content files land on disk before the debounced store.json save, so a
    /// crash in that window strands files no item references. Sweep them at
    /// launch — skipping anything recent, which might belong to a capture
    /// whose store.json entry simply hasn't been written yet.
    private func collectOrphanedContentFiles() {
        let referenced = Set(items.flatMap {
            [$0.rtfFile, $0.imageFile, $0.thumbFile].compactMap { $0 }
        })
        let dir = contentDir
        let cutoff = Date().addingTimeInterval(-3600)
        diskQueue.async {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }
            for url in files where !referenced.contains(url.lastPathComponent) {
                guard let modified = try? url.resourceValues(
                          forKeys: [.contentModificationDateKey]).contentModificationDate,
                      modified < cutoff
                else { continue }
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Mutations

    /// Insert a freshly captured item at the front of history. If an item with
    /// the same content already exists in history, it is moved to the front
    /// instead (and the new item's content files are discarded).
    public func insert(_ item: ClipItem) {
        if item.pinboardID == nil,
           let idx = items.firstIndex(where: { $0.pinboardID == nil && $0.contentHash == item.contentHash }) {
            var existing = items.remove(at: idx)
            existing.createdAt = item.createdAt
            // The re-copy may come from a different app; refresh the card's
            // color and icon along with the timestamp.
            existing.sourceAppBundleID = item.sourceAppBundleID
            existing.sourceAppName = item.sourceAppName
            items.insert(existing, at: 0)
            deleteContentFiles(of: item)
        } else {
            items.insert(item, at: 0)
        }
        enforceLimit()
        scheduleSave()
    }

    public func delete(_ id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        deleteContentFiles(of: item)
        scheduleSave()
    }

    public func clearHistory() {
        for item in items where item.pinboardID == nil {
            deleteContentFiles(of: item)
        }
        items.removeAll { $0.pinboardID == nil }
        scheduleSave()
    }

    /// Move an item to a pinboard (or back to history with nil).
    public func setPinboard(_ id: UUID, to pinboardID: UUID?) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].pinboardID = pinboardID
        scheduleSave()
    }

    @discardableResult
    public func addPinboard(name: String) -> Pinboard {
        // Prefer a palette color no other board is using; fall back to
        // round-robin once all sixteen are taken.
        let used = Set(pinboards.map(\.colorHex))
        let hex = AppColors.palette.first { !used.contains($0) }
            ?? AppColors.palette[pinboards.count % AppColors.palette.count]
        let board = Pinboard(name: name, colorHex: hex)
        pinboards.append(board)
        scheduleSave()
        return board
    }

    public func renamePinboard(_ id: UUID, to name: String) {
        guard let idx = pinboards.firstIndex(where: { $0.id == id }) else { return }
        pinboards[idx].name = name
        scheduleSave()
    }

    /// Sets or clears a user-assigned title on an item (⌘R).
    public func renameItem(_ id: UUID, title: String?) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].title = title
        scheduleSave()
    }

    /// Deleting a board moves its items back to history (safer than deleting them).
    public func deletePinboard(_ id: UUID) {
        pinboards.removeAll { $0.id == id }
        for idx in items.indices where items[idx].pinboardID == id {
            items[idx].pinboardID = nil
        }
        enforceLimit()
        scheduleSave()
    }

    // MARK: - Content files

    public func contentURL(_ filename: String) -> URL {
        contentDir.appendingPathComponent(filename)
    }

    private func deleteContentFiles(of item: ClipItem) {
        for name in [item.rtfFile, item.imageFile, item.thumbFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: contentURL(name))
        }
    }

    /// Walks the store file and content directory off the main thread —
    /// don't call this from a view body.
    public func computeTotalDataSize() async -> Int64 {
        let storeFile = self.storeFile
        let contentDir = self.contentDir
        return await Task.detached(priority: .utility) {
            Self.dataSize(storeFile: storeFile, contentDir: contentDir)
        }.value
    }

    private nonisolated static func dataSize(storeFile: URL, contentDir: URL) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        if let size = try? storeFile.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            total += Int64(size)
        }
        if let enumerator = fm.enumerator(at: contentDir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in enumerator {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    private func enforceLimit() {
        guard historyLimit != .max else { return }
        var historyCount = items.filter { $0.pinboardID == nil }.count
        guard historyCount > historyLimit else { return }
        // Walk from the back (oldest) evicting unpinned items.
        var idx = items.count - 1
        while historyCount > historyLimit, idx >= 0 {
            if items[idx].pinboardID == nil {
                deleteContentFiles(of: items[idx])
                items.remove(at: idx)
                historyCount -= 1
            }
            idx -= 1
        }
    }
}
