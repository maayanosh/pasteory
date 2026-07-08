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

    test("content hash is standard SHA-256 (dedup compatibility)") {
        expectEqual(ContentHasher.hash("text:hello"),
            "eadf732aba96d643feaa39909a300bc8a25b15fabdf41bf20819b8ce8fd3746f")
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

    test("parses hex colors") {
        expectEqual(parseColorString("#FF5733"),
                    ParsedColor(red: 1, green: 87.0 / 255, blue: 51.0 / 255))
        expectEqual(parseColorString("  #ff5733  "),
                    parseColorString("#FF5733"), "trims and is case-insensitive")
        expectEqual(parseColorString("#f00"), ParsedColor(red: 1, green: 0, blue: 0))
        expectEqual(parseColorString("#ff000080")?.alpha ?? -1, 128.0 / 255,
                    "8-digit hex carries alpha")
    }

    test("parses rgb/rgba and hsl/hsla") {
        expectEqual(parseColorString("rgb(255, 0, 0)"), ParsedColor(red: 1, green: 0, blue: 0))
        expectEqual(parseColorString("rgba(0, 0, 255, 0.5)"),
                    ParsedColor(red: 0, green: 0, blue: 1, alpha: 0.5))
        expectEqual(parseColorString("rgb(100%, 0%, 50%)"),
                    ParsedColor(red: 1, green: 0, blue: 0.5))
        expectEqual(parseColorString("hsl(0, 100%, 50%)"),
                    ParsedColor(red: 1, green: 0, blue: 0), "pure red")
        expectEqual(parseColorString("hsl(120, 100%, 50%)"),
                    ParsedColor(red: 0, green: 1, blue: 0), "pure green")
        expectEqual(parseColorString("hsla(240, 100%, 50%, 50%)"),
                    ParsedColor(red: 0, green: 0, blue: 1, alpha: 0.5))
    }

    test("rejects non-colors") {
        expect(parseColorString("hello") == nil)
        expect(parseColorString("#GGG123") == nil, "not hex digits")
        expect(parseColorString("#123") == nil, "shorthand needs a hex letter (issue refs)")
        expect(parseColorString("#12345") == nil, "wrong length")
        expect(parseColorString("rgb(300, 0, 0)") == nil, "channel out of range")
        expect(parseColorString("rgb(1, 2)") == nil, "too few channels")
        expect(parseColorString("hsl(400, 100%, 50%)") == nil, "hue out of range")
        expect(parseColorString("hsl(0, 1, 0.5)") == nil, "hsl needs percentages")
        expect(parseColorString("#FF5733 and more text") == nil, "must be the whole string")
    }
}
