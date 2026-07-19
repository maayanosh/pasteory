import AppKit

@MainActor
public final class IconCache {
    public static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private var pathCache: [String: NSImage] = [:]

    /// File icon for a path, cached — `NSWorkspace.icon(forFile:)` does
    /// synchronous disk I/O and must not run per card, per redraw. Callers
    /// size the result themselves (`.resizable()`).
    public func icon(forPath path: String) -> NSImage {
        if let cached = pathCache[path] { return cached }
        if pathCache.count > 512 { pathCache.removeAll() }  // crude growth cap
        let image = NSWorkspace.shared.icon(forFile: path)
        pathCache[path] = image
        return image
    }

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
