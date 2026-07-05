import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable {
    case text, richText, image, link, file
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
