import SwiftUI

public enum AppColors {
    // 16-hue palette used for card headers and pinboard tabs; every entry is a
    // distinct hue so hashed apps (and consecutive pinboards) spread out
    // instead of clustering on lookalike yellows/blues.
    public static let palette: [String] = [
        "#4A90D9", // blue
        "#E8734A", // orange
        "#4CAF6E", // green
        "#A550A7", // purple
        "#E8B93E", // yellow
        "#4CC2E8", // cyan
        "#E85C5C", // red
        "#3AB5A0", // teal
        "#5E5CE6", // indigo
        "#8FBE4F", // lime
        "#E06C9F", // pink
        "#A97B54", // brown
        "#9B8CE8", // lavender
        "#6E8CA0", // slate
        "#2E7D5B", // forest
        "#3C3C43", // gray-black
    ]

    static let overrides: [String: String] = [
        "com.apple.Safari": "#4A90D9",         // blue
        "com.google.Chrome": "#E8734A",        // orange
        "com.apple.finder": "#4CC2E8",         // cyan
        "com.apple.Notes": "#E8B93E",          // yellow
        "com.microsoft.VSCode": "#5E5CE6",     // indigo
        "com.tinyspeck.slackmacgap": "#A550A7",// purple
        "com.apple.Terminal": "#3C3C43",       // gray-black
        "com.googlecode.iterm2": "#2E7D5B",    // forest
        "com.apple.mail": "#3AB5A0",           // teal
        "com.apple.dt.Xcode": "#6E8CA0",       // slate
    ]

    /// Stable across launches (Swift's hashValue is seed-randomized per process,
    /// so we use djb2 over UTF-8 instead).
    public static func hex(for bundleID: String?) -> String {
        guard let id = bundleID, !id.isEmpty else { return "#3C3C43" }
        if let fixed = overrides[id] { return fixed }
        var h: UInt64 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt64(b) }
        return palette[Int(h % UInt64(palette.count))]
    }

    public static func color(for bundleID: String?) -> Color {
        Color(hex: hex(for: bundleID))
    }

    /// Perceived luminance in 0...1; used to pick readable header text color.
    public static func luminance(ofHex hex: String) -> Double {
        let (r, g, b) = rgb(fromHex: hex)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Readable overlay text color for a hex background.
    public static func readableTextColor(onHex hex: String) -> Color {
        luminance(ofHex: hex) > 0.6 ? .black : .white
    }

    static func rgb(fromHex hex: String) -> (Double, Double, Double) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return (0, 0, 0) }
        return (
            Double((v >> 16) & 0xFF) / 255.0,
            Double((v >> 8) & 0xFF) / 255.0,
            Double(v & 0xFF) / 255.0
        )
    }
}

public extension Color {
    init(hex: String) {
        let (r, g, b) = AppColors.rgb(fromHex: hex)
        self.init(red: r, green: g, blue: b)
    }
}

public extension ParsedColor {
    /// Readable overlay text color on top of this color (swatch cards).
    var readableTextColor: Color {
        luminance > 0.6 ? .black : .white
    }
}
