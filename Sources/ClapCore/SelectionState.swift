import Foundation
import Observation

@Observable
@MainActor
public final class SelectionState {
    public var query = ""
    public var selectedTab: UUID?          // nil = History
    public var selectionID: UUID?
    public var multiSelection: Set<UUID> = []  // ⌘-click additions, pasted in order on Return
    public var showNumbers = false         // ⌘ held → quick-paste badges
    public var searchFocused = false
    public var previewItem: ClipItem?

    @ObservationIgnored public let store: Store
    @ObservationIgnored public var paster: Paster?

    public init(store: Store) {
        self.store = store
    }

    // MARK: - Filtering (pure, unit-tested)

    public static func matches(_ item: ClipItem, query: String) -> Bool {
        let q = query.lowercased()
        if let text = item.text, text.lowercased().contains(q) { return true }
        if let app = item.sourceAppName, app.lowercased().contains(q) { return true }
        return item.kind.rawValue.lowercased().contains(q)
    }

    public static func filter(items: [ClipItem], tab: UUID?, query: String) -> [ClipItem] {
        items.filter { $0.pinboardID == tab }
            .filter { query.isEmpty || matches($0, query: query) }
    }

    public var filteredItems: [ClipItem] {
        Self.filter(items: store.items, tab: selectedTab, query: query)
    }

    // MARK: - Panel lifecycle

    public func panelDidShow() {
        query = ""
        searchFocused = false
        previewItem = nil
        selectedTab = nil
        showNumbers = false
        multiSelection = []
        selectionID = filteredItems.first?.id
    }

    // MARK: - Selection

    public var selectedItem: ClipItem? {
        let visible = filteredItems
        guard let id = selectionID else { return visible.first }
        return visible.first { $0.id == id } ?? visible.first
    }

    public func moveSelection(by delta: Int) {
        let visible = filteredItems
        guard !visible.isEmpty else { return }
        guard let current = visible.firstIndex(where: { $0.id == selectionID }) else {
            // Stale/absent selection: land on the first card instead of
            // treating it as index 0 and skipping ahead.
            selectionID = visible.first?.id
            return
        }
        let next = min(max(current + delta, 0), visible.count - 1)
        selectionID = visible[next].id
    }

    public func ensureSelectionValid() {
        let visible = filteredItems
        if selectionID == nil || !visible.contains(where: { $0.id == selectionID }) {
            selectionID = visible.first?.id
        }
    }

    // MARK: - Multi-selection (⌘-click), pasted in on-screen order

    public func toggleMultiSelect(_ id: UUID) {
        if multiSelection.contains(id) {
            multiSelection.remove(id)
        } else {
            multiSelection.insert(id)
        }
    }

    public func clearMultiSelection() {
        multiSelection.removeAll()
    }

    /// Selected items in on-screen (left-to-right) order. Re-derived from
    /// `filteredItems` each time, so items hidden by a tab/search change drop
    /// out automatically rather than being pasted from a stale reference.
    public var orderedMultiSelection: [ClipItem] {
        guard !multiSelection.isEmpty else { return [] }
        return filteredItems.filter { multiSelection.contains($0.id) }
    }

    // MARK: - Actions (delegate to Paster)

    public func pasteSelected(plainText: Bool = false) {
        guard let item = selectedItem else { return }
        paster?.paste(item, plainText: plainText)
    }

    /// Pastes the multi-selection in order, one at a time, each after the
    /// previous paste has had time to land. Falls back to the single
    /// selection when nothing is multi-selected.
    public func pasteMultiSelection(plainText: Bool = false) {
        let items = orderedMultiSelection
        guard !items.isEmpty else { return pasteSelected(plainText: plainText) }
        clearMultiSelection()
        pasteSequentially(items, index: 0, plainText: plainText)
    }

    private func pasteSequentially(_ items: [ClipItem], index: Int, plainText: Bool) {
        guard index < items.count else { return }
        paster?.paste(items[index], plainText: plainText)
        let next = index + 1
        guard next < items.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.pasteSequentially(items, index: next, plainText: plainText)
        }
    }

    public func paste(at index: Int, plainText: Bool = false) {
        let visible = filteredItems
        guard visible.indices.contains(index) else { return }
        paster?.paste(visible[index], plainText: plainText)
    }

    public func copySelected() {
        guard let item = selectedItem else { return }
        paster?.copy(item, plainText: false)
    }

    public func deleteSelected() {
        guard let item = selectedItem else { return }
        // Keep a sensible selection after removal.
        let visible = filteredItems
        if let idx = visible.firstIndex(of: item) {
            let nextIdx = idx + 1 < visible.count ? idx + 1 : idx - 1
            selectionID = visible.indices.contains(nextIdx) ? visible[nextIdx].id : nil
        }
        store.delete(item.id)
        if previewItem?.id == item.id { previewItem = nil }
    }

    public func appendToQuery(_ chars: String) {
        query += chars
        searchFocused = true
        ensureSelectionValid()
    }

    // MARK: - Arbitrary-item paste/copy (double-click, context menus)

    public func paste(_ item: ClipItem, plainText: Bool = false) {
        paster?.paste(item, plainText: plainText)
    }

    public func copy(_ item: ClipItem) {
        paster?.copy(item, plainText: false)
    }
}
