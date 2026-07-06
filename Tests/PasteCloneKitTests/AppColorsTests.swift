import Foundation

@MainActor
func appColorsTests() {
    test("known app overrides") {
        expectEqual(AppColors.hex(for: "com.apple.Safari"), "#4A90D9")
        expectEqual(AppColors.hex(for: "com.apple.Terminal"), "#3C3C43")
    }

    test("unknown app is deterministic and in palette") {
        let a = AppColors.hex(for: "com.random.someapp")
        let b = AppColors.hex(for: "com.random.someapp")
        expectEqual(a, b, "stable across calls (djb2, not seeded hashValue)")
        expect(AppColors.palette.contains(a))
    }

    test("nil bundle id falls back to gray") {
        expectEqual(AppColors.hex(for: nil), "#3C3C43")
    }

    test("palette entries are unique") {
        expectEqual(Set(AppColors.palette).count, AppColors.palette.count,
                    "duplicate hues defeat the point of a bigger palette")
    }

    test("luminance drives header text color") {
        expect(AppColors.luminance(ofHex: "#FFFFFF") > 0.9)
        expect(AppColors.luminance(ofHex: "#000000") < 0.1)
        expect(AppColors.luminance(ofHex: "#E8B93E") > 0.6, "yellow header → black text")
        expect(AppColors.luminance(ofHex: "#4A90D9") < 0.6, "blue header → white text")
    }
}
