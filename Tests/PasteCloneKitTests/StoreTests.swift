import Foundation

@MainActor
private func withTempStore(_ body: (Store) throws -> Void) rethrows {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteCloneTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(Store(directory: dir))
}

@MainActor
private func makeItem(_ text: String, pinboardID: UUID? = nil) -> ClipItem {
    ClipItem(kind: .text, text: text, pinboardID: pinboardID,
             contentHash: ContentHasher.hash("text:" + text))
}

@MainActor
func storeTests() {
    test("insert puts newest first") {
        withTempStore { store in
            store.insert(makeItem("one"))
            store.insert(makeItem("two"))
            expectEqual(store.items.compactMap(\.text), ["two", "one"])
        }
    }

    test("dedup moves existing to front, keeps identity") {
        withTempStore { store in
            store.insert(makeItem("one"))
            store.insert(makeItem("two"))
            guard let originalID = store.items.last?.id else {
                return expect(false, "missing item")
            }
            store.insert(makeItem("one")) // re-copy
            expectEqual(store.items.count, 2)
            expectEqual(store.items.first?.text, "one")
            expectEqual(store.items.first?.id, originalID, "should move, not recreate")
        }
    }

    test("dedup discards the duplicate's content files") {
        try withTempStore { store in
            store.insert(makeItem("keep"))
            let filename = "dupe.rtf"
            try Data("x".utf8).write(to: store.contentURL(filename))
            var dupe = makeItem("keep")
            dupe.rtfFile = filename
            store.insert(dupe)
            expectEqual(store.items.count, 1)
            expect(!FileManager.default.fileExists(atPath: store.contentURL(filename).path))
        }
    }

    test("history limit evicts oldest unpinned") {
        withTempStore { store in
            store.historyLimit = 3
            let board = store.addPinboard(name: "Keep")
            store.insert(makeItem("pinned", pinboardID: board.id))
            for i in 1...5 { store.insert(makeItem("item\(i)")) }
            let history = store.items.filter { $0.pinboardID == nil }
            expectEqual(history.count, 3)
            expectEqual(history.compactMap(\.text), ["item5", "item4", "item3"])
            expect(store.items.contains { $0.text == "pinned" }, "pinned survives eviction")
        }
    }

    test("eviction deletes content files") {
        try withTempStore { store in
            store.historyLimit = 1
            let filename = "old.png"
            try Data("img".utf8).write(to: store.contentURL(filename))
            var old = makeItem("old")
            old.imageFile = filename
            store.insert(old)
            store.insert(makeItem("new"))
            expect(!FileManager.default.fileExists(atPath: store.contentURL(filename).path))
        }
    }

    test("delete removes item and files") {
        try withTempStore { store in
            let filename = "gone.png"
            try Data("img".utf8).write(to: store.contentURL(filename))
            var item = makeItem("bye")
            item.imageFile = filename
            store.insert(item)
            store.delete(item.id)
            expect(store.items.isEmpty)
            expect(!FileManager.default.fileExists(atPath: store.contentURL(filename).path))
        }
    }

    test("clear history keeps pinned") {
        withTempStore { store in
            let board = store.addPinboard(name: "Snippets")
            store.insert(makeItem("history1"))
            store.insert(makeItem("pinned", pinboardID: board.id))
            store.insert(makeItem("history2"))
            store.clearHistory()
            expectEqual(store.items.count, 1)
            expectEqual(store.items.first?.text, "pinned")
        }
    }

    test("persistence round trip") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteCloneTests-persist-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = Store(directory: dir)
        let board = store.addPinboard(name: "Snips")
        store.insert(makeItem("hello"))
        guard let itemID = store.items.first?.id else {
            return expect(false, "missing item")
        }
        store.setPinboard(itemID, to: board.id)
        store.saveNow()
        store.flush() // saves are async; wait for the bytes before reloading

        let reloaded = Store(directory: dir)
        expectEqual(reloaded.items.count, 1)
        expectEqual(reloaded.items.first?.text, "hello")
        expectEqual(reloaded.items.first?.pinboardID, board.id)
        expectEqual(reloaded.pinboards.map(\.name), ["Snips"])
    }

    test("loads a legacy store.json without a version field") {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteCloneTests-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Shape written by pre-versioned builds: no "version", no "files",
        // no "byteSize". Dates encode as secondsSinceReferenceDate.
        let json = """
        {"items":[{"id":"\(UUID().uuidString)","kind":"text","text":"old",\
        "createdAt":0,"contentHash":"abc"}],"pinboards":[]}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("store.json"))

        let store = Store(directory: dir)
        expectEqual(store.items.count, 1)
        expectEqual(store.items.first?.text, "old")
        let corruptBackups = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.hasPrefix("store.json.corrupt") } ?? []
        expect(corruptBackups.isEmpty, "legacy file must not be treated as corrupt")
    }

    test("delete pinboard moves items to history") {
        withTempStore { store in
            let board = store.addPinboard(name: "Temp")
            store.insert(makeItem("was pinned", pinboardID: board.id))
            store.deletePinboard(board.id)
            expect(store.pinboards.isEmpty)
            expectEqual(store.items.first?.pinboardID, nil)
        }
    }

    test("rename pinboard") {
        withTempStore { store in
            let board = store.addPinboard(name: "Old")
            store.renamePinboard(board.id, to: "New")
            expectEqual(store.pinboards.first?.name, "New")
        }
    }

    test("rename item sets title") {
        withTempStore { store in
            store.insert(makeItem("hello"))
            guard let id = store.items.first?.id else { return expect(false, "missing item") }
            store.renameItem(id, title: "My Snippet")
            expectEqual(store.items.first?.title, "My Snippet")
            store.renameItem(id, title: nil)
            expectEqual(store.items.first?.title, nil)
        }
    }

    test("deleting an item also deletes its thumbnail file") {
        try withTempStore { store in
            let imageFilename = "full.png"
            let thumbFilename = "full-thumb.png"
            try Data("img".utf8).write(to: store.contentURL(imageFilename))
            try Data("thumb".utf8).write(to: store.contentURL(thumbFilename))
            var item = makeItem("img-item")
            item.imageFile = imageFilename
            item.thumbFile = thumbFilename
            store.insert(item)
            store.delete(item.id)
            expect(!FileManager.default.fileExists(atPath: store.contentURL(imageFilename).path))
            expect(!FileManager.default.fileExists(atPath: store.contentURL(thumbFilename).path))
        }
    }

    test("eviction also deletes the thumbnail file") {
        try withTempStore { store in
            store.historyLimit = 1
            let thumbFilename = "old-thumb.png"
            try Data("thumb".utf8).write(to: store.contentURL(thumbFilename))
            var old = makeItem("old")
            old.thumbFile = thumbFilename
            store.insert(old)
            store.insert(makeItem("new"))
            expect(!FileManager.default.fileExists(atPath: store.contentURL(thumbFilename).path))
        }
    }
}
