import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable {
    case text, richText, image, link, file, color
}

public struct ClipItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public var kind: ClipKind
    public var text: String?          // plain text / URL string / file path(s)
    public var rtfFile: String?       // filename in content dir
    public var imageFile: String?     // filename in content dir
    public var thumbFile: String?     // small preview filename in content dir (images only)
    public var title: String?         // optional user-assigned label (⌘R)
    public var sourceAppBundleID: String?
    public var sourceAppName: String?
    public var createdAt: Date
    public var pinboardID: UUID?      // nil = history
    public var contentHash: String

    public init(
        id: UUID = UUID(),
        kind: ClipKind,
        text: String? = nil,
        rtfFile: String? = nil,
        imageFile: String? = nil,
        thumbFile: String? = nil,
        title: String? = nil,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        createdAt: Date = Date(),
        pinboardID: UUID? = nil,
        contentHash: String
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.rtfFile = rtfFile
        self.imageFile = imageFile
        self.thumbFile = thumbFile
        self.title = title
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.pinboardID = pinboardID
        self.contentHash = contentHash
    }
}

public struct Pinboard: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

public enum ContentHasher {
    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func hash(_ string: String) -> String {
        hash(Data(string.utf8))
    }
}

/// True when the string is a single http(s) URL and nothing else.
public func isLinkString(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, !t.contains(" "), !t.contains("\n"),
          let url = URL(string: t),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          url.host != nil
    else { return false }
    return true
}

/// Compact relative timestamps like Paste's cards: "now", "5m", "2h", "3d".
public func relativeTimeString(from date: Date, now: Date = Date()) -> String {
    let s = max(0, Int(now.timeIntervalSince(date)))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return "\(s / 86400)d"
}

/// Rough heuristic for rendering text previews in monospace.
public func looksLikeCode(_ s: String) -> Bool {
    if s.contains("{") || s.contains(";") { return true }
    return s.split(separator: "\n").contains { $0.hasPrefix("    ") }
}

// MARK: - Color detection (swatch cards)

/// A color parsed from clipboard text like "#FF5733", "rgb(255, 87, 51)" or
/// "hsl(11, 100%, 60%)". Components are 0...1.
public struct ParsedColor: Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Perceived luminance 0...1, for choosing readable overlay text.
    public var luminance: Double { 0.299 * red + 0.587 * green + 0.114 * blue }
}

/// Parses a string that is exactly one CSS-style color: #hex (3/4/6/8 digits),
/// rgb()/rgba(), or hsl()/hsla(). Returns nil for anything else.
public func parseColorString(_ s: String) -> ParsedColor? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard t.count >= 4, t.count <= 48 else { return nil }
    if t.hasPrefix("#") { return parseHexColor(String(t.dropFirst())) }
    if t.hasPrefix("rgb") { return parseRGBFunction(t) }
    if t.hasPrefix("hsl") { return parseHSLFunction(t) }
    return nil
}

private func parseHexColor(_ hex: String) -> ParsedColor? {
    guard hex.allSatisfy(\.isHexDigit) else { return nil }
    func channel(_ pair: String) -> Double {
        Double(UInt8(pair, radix: 16) ?? 0) / 255
    }
    switch hex.count {
    case 3, 4:
        // Shorthand must contain a hex letter so things like issue references
        // ("#123", "#1234") don't turn into swatches.
        guard hex.contains(where: \.isLetter) else { return nil }
        let c = hex.map { channel("\($0)\($0)") }
        return ParsedColor(red: c[0], green: c[1], blue: c[2],
                           alpha: hex.count == 4 ? c[3] : 1)
    case 6, 8:
        var c: [Double] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            c.append(channel(String(hex[idx..<next])))
            idx = next
        }
        return ParsedColor(red: c[0], green: c[1], blue: c[2],
                           alpha: c.count == 4 ? c[3] : 1)
    default:
        return nil
    }
}

/// Splits "name(a, b, c)" / "namea(a b c / d)" into its argument strings.
private func functionArguments(_ t: String, name: String) -> [String]? {
    for prefix in [name + "a(", name + "("] where t.hasPrefix(prefix) && t.hasSuffix(")") {
        let inner = t.dropFirst(prefix.count).dropLast()
        let parts = inner
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0 == " " })
            .map(String.init)
        return parts.isEmpty ? nil : parts
    }
    return nil
}

/// "0.5", "50%" → 0.5; nil when malformed or out of 0...1.
private func unitValue(_ s: String) -> Double? {
    let value = s.hasSuffix("%")
        ? Double(String(s.dropLast())).map { $0 / 100 }
        : Double(s)
    guard let value, (0...1).contains(value) else { return nil }
    return value
}

private func parseRGBFunction(_ t: String) -> ParsedColor? {
    guard let args = functionArguments(t, name: "rgb"),
          args.count == 3 || args.count == 4
    else { return nil }
    func channel(_ s: String) -> Double? {
        if s.hasSuffix("%") { return unitValue(s) }
        guard let v = Double(s), (0...255).contains(v) else { return nil }
        return v / 255
    }
    guard let r = channel(args[0]), let g = channel(args[1]), let b = channel(args[2]),
          let a = args.count == 4 ? unitValue(args[3]) : 1
    else { return nil }
    return ParsedColor(red: r, green: g, blue: b, alpha: a)
}

private func parseHSLFunction(_ t: String) -> ParsedColor? {
    guard let args = functionArguments(t, name: "hsl"),
          args.count == 3 || args.count == 4,
          let h = Double(args[0].replacingOccurrences(of: "deg", with: "")),
          (0...360).contains(h),
          args[1].hasSuffix("%"), args[2].hasSuffix("%"),
          let s = unitValue(args[1]), let l = unitValue(args[2]),
          let a = args.count == 4 ? unitValue(args[3]) : 1
    else { return nil }

    let c = (1 - abs(2 * l - 1)) * s
    let hp = h / 60
    let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
    let (r1, g1, b1): (Double, Double, Double)
    switch Int(hp) % 6 {
    case 0: (r1, g1, b1) = (c, x, 0)
    case 1: (r1, g1, b1) = (x, c, 0)
    case 2: (r1, g1, b1) = (0, c, x)
    case 3: (r1, g1, b1) = (0, x, c)
    case 4: (r1, g1, b1) = (x, 0, c)
    default: (r1, g1, b1) = (c, 0, x)
    }
    let m = l - c / 2
    return ParsedColor(red: r1 + m, green: g1 + m, blue: b1 + m, alpha: a)
}
