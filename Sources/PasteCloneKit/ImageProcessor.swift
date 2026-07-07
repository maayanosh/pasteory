import AppKit

@MainActor
enum ImageProcessor {
    static let maxBytes = 20 * 1024 * 1024

    /// Builds an image ClipItem from a single image file URL, or nil if the file
    /// isn't an image, is too large, or can't be converted.
    static func makeItem(
        fromImageFile url: URL,
        store: Store,
        bundleID: String?,
        appName: String?
    ) -> ClipItem? {
        guard let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
              UTTypeConformsTo(uti as CFString, "public.image" as CFString),
              let image = NSImage(contentsOf: url),
              let png = pngData(from: image),
              png.count <= maxBytes
        else { return nil }

        return makeItem(fromPNG: png, image: image, store: store, bundleID: bundleID, appName: appName)
    }

    /// Builds an image ClipItem from raw PNG or TIFF pasteboard data, or nil if
    /// the data is too large or can't be decoded.
    static func makeItem(
        fromPasteboardData data: Data,
        store: Store,
        bundleID: String?,
        appName: String?
    ) -> ClipItem? {
        guard data.count <= maxBytes,
              let image = NSImage(data: data),
              let png = pngData(from: image)
        else { return nil }

        return makeItem(fromPNG: png, image: image, store: store, bundleID: bundleID, appName: appName)
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func thumbnailData(from image: NSImage, maxDimension: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let targetSize = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        let thumb = NSImage(size: targetSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1)
        thumb.unlockFocus()

        return pngData(from: thumb)
    }

    // MARK: - Private

    private static func makeItem(
        fromPNG png: Data,
        image: NSImage,
        store: Store,
        bundleID: String?,
        appName: String?
    ) -> ClipItem? {
        let filename = UUID().uuidString + ".png"
        guard (try? png.write(to: store.contentURL(filename))) != nil else { return nil }

        // Card thumbnails render at 240×214 pt (up to 2× on Retina); a small
        // pre-scaled copy avoids decoding the full image on every scroll redraw.
        var thumbFilename: String?
        if let thumbPNG = thumbnailData(from: image, maxDimension: 480) {
            let name = UUID().uuidString + "-thumb.png"
            if (try? thumbPNG.write(to: store.contentURL(name))) != nil {
                thumbFilename = name
            }
        }

        return ClipItem(
            kind: .image, imageFile: filename, thumbFile: thumbFilename,
            sourceAppBundleID: bundleID, sourceAppName: appName,
            contentHash: ContentHasher.hash(png)
        )
    }
}
