import Foundation

@MainActor
private func item(_ text: String, app: String? = nil, kind: ClipKind = .text,
                  pinboardID: UUID? = nil) -> ClipItem {
    ClipItem(kind: kind, text: text, sourceAppName: app, pinboardID: pinboardID,
             contentHash: ContentHasher.hash(text))
}

@MainActor
func filterTests() {
    test("empty query returns items for the active tab only") {
        let board = UUID()
        let items = [item("a"), item("b", pinboardID: board)]
        expectEqual(AppState.filter(items: items, tab: nil, query: "").compactMap(\.text), ["a"])
        expectEqual(AppState.filter(items: items, tab: board, query: "").compactMap(\.text), ["b"])
    }

    test("query matches text, case-insensitive") {
        let items = [item("Hello World"), item("goodbye")]
        expectEqual(AppState.filter(items: items, tab: nil, query: "hello").compactMap(\.text),
                    ["Hello World"])
    }

    test("query matches source app name") {
        let items = [item("xyz", app: "Safari"), item("abc", app: "Terminal")]
        expectEqual(AppState.filter(items: items, tab: nil, query: "safari").compactMap(\.text),
                    ["xyz"])
    }

    test("query matches kind") {
        let items = [item("https://x.co", kind: .link), item("plain")]
        expectEqual(AppState.filter(items: items, tab: nil, query: "link").compactMap(\.text),
                    ["https://x.co"])
    }

    test("no matches yields empty") {
        let items = [item("aaa"), item("bbb")]
        expect(AppState.filter(items: items, tab: nil, query: "zzz").isEmpty)
    }

    test("selection movement clamps at both ends") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteCloneTests-sel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir)
        guard let defaults = UserDefaults(suiteName: "test-\(UUID())") else {
            return expect(false, "no defaults suite")
        }
        let state = AppState(store: store, settings: Settings(defaults: defaults))
        for i in 1...3 {
            store.insert(ClipItem(kind: .text, text: "i\(i)",
                                  contentHash: ContentHasher.hash("i\(i)")))
        }
        state.panelDidShow()
        expectEqual(state.selectedItem?.text, "i3", "newest first, selected on show")

        state.moveSelection(by: 1)
        expectEqual(state.selectedItem?.text, "i2")
        state.moveSelection(by: 1)
        state.moveSelection(by: 1) // clamps at end
        expectEqual(state.selectedItem?.text, "i1")
        state.moveSelection(by: -5) // clamps at start
        expectEqual(state.selectedItem?.text, "i3")
    }

    test("multi-selection toggles and orders left-to-right on screen") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteCloneTests-multisel-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir)
        guard let defaults = UserDefaults(suiteName: "test-\(UUID())") else {
            return expect(false, "no defaults suite")
        }
        let state = AppState(store: store, settings: Settings(defaults: defaults))
        for i in 1...3 {
            store.insert(ClipItem(kind: .text, text: "i\(i)",
                                  contentHash: ContentHasher.hash("i\(i)")))
        }
        // On-screen order (newest first): i3, i2, i1.
        let ids = store.items.map(\.id) // [i3, i2, i1]
        state.panelDidShow()
        expect(state.multiSelection.isEmpty, "cleared on panel show")

        state.toggleMultiSelect(ids[2]) // select i1 first...
        state.toggleMultiSelect(ids[0]) // ...then i3
        expectEqual(state.orderedMultiSelection.compactMap(\.text), ["i3", "i1"],
                    "order follows on-screen position, not selection order")

        state.toggleMultiSelect(ids[0]) // deselect i3
        expectEqual(state.orderedMultiSelection.compactMap(\.text), ["i1"])
    }

    test("multi-selection drops items hidden by the current filter") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteCloneTests-multisel2-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = Store(directory: dir)
        guard let defaults = UserDefaults(suiteName: "test-\(UUID())") else {
            return expect(false, "no defaults suite")
        }
        let state = AppState(store: store, settings: Settings(defaults: defaults))
        store.insert(ClipItem(kind: .text, text: "apple", contentHash: ContentHasher.hash("apple")))
        store.insert(ClipItem(kind: .text, text: "banana", contentHash: ContentHasher.hash("banana")))
        state.panelDidShow()
        for id in store.items.map(\.id) { state.toggleMultiSelect(id) }
        expectEqual(state.orderedMultiSelection.count, 2)

        state.query = "apple"
        expectEqual(state.orderedMultiSelection.compactMap(\.text), ["apple"],
                    "filtered-out selection no longer shows up in paste order")
    }
}
