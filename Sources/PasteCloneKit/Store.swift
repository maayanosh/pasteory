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

    struct Snapshot: Codable {
        var items: [ClipItem]
        var pinboards: [Pinboard]
    }

    public init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PasteClone")
        try? FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storeFile),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        items = snapshot.items
        pinboards = snapshot.pinboards
    }

    public func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let snapshot = Snapshot(items: items, pinboards: pinboards)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storeFile, options: .atomic)
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
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
        let hex = AppColors.palette[pinboards.count % AppColors.palette.count]
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

    private func enforceLimit() {
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
