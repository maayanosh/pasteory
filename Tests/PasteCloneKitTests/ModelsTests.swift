import Foundation

@MainActor
func modelsTests() {
    test("detects plain http(s) links") {
        expect(isLinkString("https://example.com/path?q=1"))
        expect(isLinkString("http://example.com"))
        expect(isLinkString("  https://example.com  "), "trims whitespace")
    }

    test("rejects non-links") {
        expect(!isLinkString("hello world"))
        expect(!isLinkString("check https://example.com out"), "embedded URL")
        expect(!isLinkString("ftp://example.com"))
        expect(!isLinkString("file:///tmp/x"))
        expect(!isLinkString("https://example.com\nsecond line"))
        expect(!isLinkString(""))
        expect(!isLinkString("https://"), "no host")
    }

    test("content hash is stable and distinct") {
        expectEqual(ContentHasher.hash("abc"), ContentHasher.hash("abc"))
        expect(ContentHasher.hash("abc") != ContentHasher.hash("abd"))
        expectEqual(ContentHasher.hash("abc").count, 64, "sha256 hex length")
    }

    test("relative time buckets") {
        let now = Date()
        expectEqual(relativeTimeString(from: now, now: now), "now")
        expectEqual(relativeTimeString(from: now.addingTimeInterval(-30), now: now), "now")
        expectEqual(relativeTimeString(from: now.addingTimeInterval(-90), now: now), "1m")
        expectEqual(relativeTimeString(from: now.addingTimeInterval(-3600 * 2), now: now), "2h")
        expectEqual(relativeTimeString(from: now.addingTimeInterval(-86400 * 3), now: now), "3d")
        expectEqual(relativeTimeString(from: now.addingTimeInterval(60), now: now), "now",
                    "future dates clamp to now")
    }

    test("code heuristic") {
        expect(looksLikeCode("func x() { return 1 }"))
        expect(looksLikeCode("a = 1;"))
        expect(looksLikeCode("def f():\n    pass"))
        expect(!looksLikeCode("Just a normal sentence."))
    }
}
