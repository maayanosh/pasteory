import SwiftUI
#if canImport(ClapCore)
import ClapCore
#endif

public enum AppColors {
    public static var palette: [String] { Palette.palette }
    public static func hex(for bundleID: String?) -> String { Palette.hex(for: bundleID) }
    public static func luminance(ofHex hex: String) -> Double { Palette.luminance(ofHex: hex) }

    public static func color(for bundleID: String?) -> Color {
        Color(hex: hex(for: bundleID))
    }
}

public extension Color {
    init(hex: String) {
        let (r, g, b) = Palette.rgb(fromHex: hex)
        self.init(red: r, green: g, blue: b)
    }
}
