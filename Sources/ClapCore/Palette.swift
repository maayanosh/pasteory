import Foundation

/// Pure color math shared across platforms. No UI-framework colors here.
public enum Palette {
    public static let palette: [String] = [
        "#4A90D9", "#E8734A", "#4CAF6E", "#A550A7", "#E8B93E", "#4CC2E8",
        "#E85C5C", "#3AB5A0", "#5E5CE6", "#8FBE4F", "#E06C9F", "#A97B54",
        "#9B8CE8", "#6E8CA0", "#2E7D5B", "#3C3C43",
    ]

    static let overrides: [String: String] = [
        "com.apple.Safari": "#4A90D9",
        "com.google.Chrome": "#E8734A",
        "com.apple.finder": "#4CC2E8",
        "com.apple.Notes": "#E8B93E",
        "com.microsoft.VSCode": "#5E5CE6",
        "com.tinyspeck.slackmacgap": "#A550A7",
        "com.apple.Terminal": "#3C3C43",
        "com.googlecode.iterm2": "#2E7D5B",
        "com.apple.mail": "#3AB5A0",
        "com.apple.dt.Xcode": "#6E8CA0",
    ]

    /// Stable across launches (djb2 over UTF-8; Swift's hashValue is seeded).
    public static func hex(for bundleID: String?) -> String {
        guard let id = bundleID, !id.isEmpty else { return "#3C3C43" }
        if let fixed = overrides[id] { return fixed }
        var h: UInt64 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt64(b) }
        return palette[Int(h % UInt64(palette.count))]
    }

    public static func luminance(ofHex hex: String) -> Double {
        let (r, g, b) = rgb(fromHex: hex)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    public static func rgb(fromHex hex: String) -> (Double, Double, Double) {
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
