import SwiftUI

public enum AppColors {
    // 10-hue palette used for card headers; index chosen by stable hash of bundle id.
    public static let palette: [String] = [
        "#4A90D9", // blue
        "#E8B93E", // yellow
        "#5FB3E8", // sky
        "#E8A33E", // amber
        "#5E5CE6", // indigo
        "#A550A7", // purple
        "#3C3C43", // gray-black
        "#4CC2E8", // cyan
        "#E85C5C", // red
        "#4CAF6E", // green
    ]

    static let overrides: [String: String] = [
        "com.apple.Safari": "#4A90D9",
        "com.google.Chrome": "#E8B93E",
        "com.apple.finder": "#5FB3E8",
        "com.apple.Notes": "#E8A33E",
        "com.microsoft.VSCode": "#5E5CE6",
        "com.tinyspeck.slackmacgap": "#A550A7",
        "com.apple.Terminal": "#3C3C43",
        "com.googlecode.iterm2": "#3C3C43",
        "com.apple.mail": "#4CC2E8",
        "com.apple.dt.Xcode": "#4A90D9",
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
