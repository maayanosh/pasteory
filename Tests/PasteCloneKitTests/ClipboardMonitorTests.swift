import AppKit

/// In-memory pasteboard so capture logic can be tested without touching the
/// real (global, mutable) system pasteboard.
private final class FakePasteboard: PasteboardReading {
    var changeCount = 1
    var typeIdentifiers: [String] = []
    var strings: [NSPasteboard.PasteboardType: String] = [:]
    var datas: [NSPasteboard.PasteboardType: Data] = [:]
    var urls: [URL] = []

    func data(forType type: NSPasteboard.PasteboardType) -> Data? { datas[type] }
    func string(forType type: NSPasteboard.PasteboardType) -> String? { strings[type] }
    func fileURLs() -> [URL] { urls }
}

@MainActor
private func withMonitor(
    _ body: (ClipboardMonitor, FakePasteboard, Store, Settings) throws -> Void
) rethrows {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PasteCloneTests-monitor-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    guard let defaults = UserDefaults(suiteName: "test-\(UUID())") else {
        return expect(false, "no defaults suite")
    }
    let store = Store(directory: dir)
    let settings = Settings(defaults: defaults)
    let monitor = ClipboardMonitor(store: store, settings: settings, initialChangeCount: 0)
    try body(monitor, FakePasteboard(), store, settings)
}

@MainActor
func clipboardMonitorTests() {
    test("captures plain text") {
        withMonitor { monitor, pb, store, _ in
            pb.strings[.string] = "hello world"
            monitor.check(pasteboard: pb)
            expectEqual(store.items.first?.kind, .text)
            expectEqual(store.items.first?.text, "hello world")
        }
    }

    test("classifies links and colors") {
        withMonitor { monitor, pb, store, _ in
            pb.strings[.string] = "https://example.com"
            monitor.check(pasteboard: pb)
            expectEqual(store.items.first?.kind, .link)

            pb.changeCount += 1
            pb.strings[.string] = "#ff5733"
            monitor.check(pasteboard: pb)
            expectEqual(store.items.first?.kind, .color)
        }
    }

    test("ignores an unchanged pasteboard") {
        withMonitor { monitor, pb, store, _ in
            pb.strings[.string] = "first"
            monitor.check(pasteboard: pb)
            pb.strings[.string] = "second" // same changeCount → not re-read
            monitor.check(pasteboard: pb)
            expectEqual(store.items.count, 1)
            expectEqual(store.items.first?.text, "first")
        }
    }

    test("skips its own paste via expectedChangeCount") {
        withMonitor { monitor, pb, store, _ in
            pb.changeCount = 7
            pb.strings[.string] = "own paste"
            monitor.expectedChangeCount = 7
            monitor.check(pasteboard: pb)
            expect(store.items.isEmpty)
        }
    }

    test("skips concealed content") {
        withMonitor { monitor, pb, store, _ in
            pb.strings[.string] = "hunter2"
            pb.typeIdentifiers = ["org.nspasteboard.ConcealedType"]
            monitor.check(pasteboard: pb)
            expect(store.items.isEmpty)
        }
    }

    test("skips while paused") {
        withMonitor { monitor, pb, store, settings in
            settings.isPaused = true
            pb.strings[.string] = "while paused"
            monitor.check(pasteboard: pb)
            expect(store.items.isEmpty)
        }
    }

    test("rich text saves an RTF sidecar file") {
        withMonitor { monitor, pb, store, _ in
            pb.strings[.string] = "styled"
            pb.datas[.rtf] = Data("{\\rtf1 styled}".utf8)
            monitor.check(pasteboard: pb)
            expectEqual(store.items.first?.kind, .richText)
            guard let rtfFile = store.items.first?.rtfFile else {
                return expect(false, "missing rtf file")
            }
            expect(FileManager.default.fileExists(atPath: store.contentURL(rtfFile).path))
        }
    }

    test("file URLs become one file card with stored paths and size") {
        try withMonitor { monitor, pb, store, _ in
            let tmp = FileManager.default.temporaryDirectory
            let a = tmp.appendingPathComponent("a-\(UUID().uuidString).txt")
            let b = tmp.appendingPathComponent("b-\(UUID().uuidString).txt")
            try Data("aa".utf8).write(to: a)
            try Data("bbbb".utf8).write(to: b)
            defer {
                try? FileManager.default.removeItem(at: a)
                try? FileManager.default.removeItem(at: b)
            }
            pb.urls = [a, b]
            monitor.check(pasteboard: pb)
            expectEqual(store.items.first?.kind, .file)
            expectEqual(store.items.first?.filePaths, [a.path, b.path])
            expectEqual(store.items.first?.byteSize, 6)
        }
    }
}
