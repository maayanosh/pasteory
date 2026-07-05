import AppKit

@MainActor
public final class IconCache {
    public static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    public func icon(forBundleID bundleID: String?) -> NSImage {
        let key = bundleID ?? "?"
        if let cached = cache[key] { return cached }
        var image: NSImage
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
                ?? NSImage()
        }
        image.size = NSSize(width: 16, height: 16)
        cache[key] = image
        return image
    }
}
