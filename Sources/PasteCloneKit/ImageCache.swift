import AppKit

/// Caches decoded thumbnail images so scrolling the card row doesn't re-read
/// and re-decode PNGs from disk on every SwiftUI redraw.
@MainActor
public final class ImageCache {
    public static let shared = ImageCache()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()

    public func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    public func clear() {
        cache.removeAllObjects()
    }
}
