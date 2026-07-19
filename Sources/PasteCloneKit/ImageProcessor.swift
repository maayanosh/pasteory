import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image decode/encode via ImageIO — no NSImage, no main-thread requirement,
/// and no full-size TIFF intermediate. Called from a background task by
/// ClipboardMonitor.
enum ImageProcessor {
    static let maxBytes = 20 * 1024 * 1024
    /// Card thumbnails render at 240×214 pt (up to 2× on Retina); a small
    /// pre-scaled copy avoids decoding the full image on every scroll redraw.
    static let thumbnailMaxPixelSize = 480

    /// Decodes image bytes, persists a PNG (plus thumbnail) into `contentDir`,
    /// and returns the item — or nil if the data isn't a decodable image, is
    /// too large, or the content file can't be written.
    static func makeItem(
        fromData data: Data,
        contentDir: URL,
        bundleID: String?,
        appName: String?
    ) -> ClipItem? {
        guard data.count <= maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        // Keep the original bytes when the clipboard already offers PNG;
        // only transcode other formats (TIFF etc.).
        let png: Data
        if CGImageSourceGetType(source) as String? == UTType.png.identifier {
            png = data
        } else {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let encoded = pngData(from: image)
            else { return nil }
            png = encoded
        }
        guard png.count <= maxBytes else { return nil }

        let filename = UUID().uuidString + ".png"
        do {
            try png.write(to: contentDir.appendingPathComponent(filename), options: .atomic)
        } catch {
            NSLog("Clap: failed to write image content file: \(error)")
            return nil
        }

        var thumbFilename: String?
        if let thumbPNG = thumbnailPNG(from: source) {
            let name = UUID().uuidString + "-thumb.png"
            if (try? thumbPNG.write(to: contentDir.appendingPathComponent(name),
                                    options: .atomic)) != nil {
                thumbFilename = name
            }
        }

        return ClipItem(
            kind: .image, imageFile: filename, thumbFile: thumbFilename,
            byteSize: Int64(png.count),
            sourceAppBundleID: bundleID, sourceAppName: appName,
            contentHash: ContentHasher.hash(png)
        )
    }

    static func pngData(from image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    private static func thumbnailPNG(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return pngData(from: thumb)
    }
}
