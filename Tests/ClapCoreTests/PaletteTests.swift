import Foundation

@MainActor
func paletteTests() {
    test("known app overrides") {
        expectEqual(Palette.hex(for: "com.apple.Safari"), "#4A90D9")
        expectEqual(Palette.hex(for: "com.apple.Terminal"), "#3C3C43")
    }

    test("unknown app is deterministic and in palette") {
        let a = Palette.hex(for: "com.random.someapp")
        let b = Palette.hex(for: "com.random.someapp")
        expectEqual(a, b, "stable across calls (djb2, not seeded hashValue)")
        expect(Palette.palette.contains(a))
    }

    test("nil bundle id falls back to gray") {
        expectEqual(Palette.hex(for: nil), "#3C3C43")
    }

    test("palette entries are unique") {
        expectEqual(Set(Palette.palette).count, Palette.palette.count,
                    "duplicate hues defeat the point of a bigger palette")
    }

    test("luminance drives header text color") {
        expect(Palette.luminance(ofHex: "#FFFFFF") > 0.9)
        expect(Palette.luminance(ofHex: "#000000") < 0.1)
        expect(Palette.luminance(ofHex: "#E8B93E") > 0.6, "yellow header → black text")
        expect(Palette.luminance(ofHex: "#4A90D9") < 0.6, "blue header → white text")
    }
}
