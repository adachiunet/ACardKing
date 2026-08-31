import Foundation
import UIKit
import ImageIO

/// Saves and loads business-card photos as JPEG files inside the app's own
/// Documents/CardImages directory. Models only ever store the filename (not a full
/// path), so the app keeps working even if iOS moves the container between launches.
enum ImageStorageService {
    private static let folderName = "CardImages"

    /// Small decoded thumbnails, keyed by filename, so scrolling the card list doesn't
    /// re-decode the same full-resolution photo on every re-render. NSCache evicts entries
    /// under memory pressure on its own, so this never needs manual trimming.
    private static let thumbnailCache = NSCache<NSString, UIImage>()

    private static var imagesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Saves the image as a JPEG with a fresh unique filename and returns that filename,
    /// or nil if the write failed.
    @discardableResult
    static func save(_ image: UIImage, quality: CGFloat = 0.85) -> String? {
        guard let data = image.jpegData(compressionQuality: quality) else { return nil }
        let filename = UUID().uuidString + ".jpg"
        let url = imagesDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return filename
        } catch {
            print("ImageStorageService.save error: \(error)")
            return nil
        }
    }

    static func load(_ filename: String?) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }
        let url = imagesDirectory.appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    /// A small (~120px) downsampled copy of the photo, for the card list / row avatar.
    /// Scanned photos are saved at full camera resolution (see `save`), so decoding the
    /// whole file just to shrink it into a 44×44 circle is wasteful and — with a list full
    /// of cards — was the main reason the app felt like it hesitated right after opening.
    /// This uses ImageIO's thumbnail generator, which downsamples while decoding instead of
    /// decoding the full image first, and caches the (tiny) result in memory.
    static func loadThumbnail(_ filename: String?, maxPixelSize: CGFloat = 120) -> UIImage? {
        guard let filename, !filename.isEmpty else { return nil }
        let cacheKey = filename as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) { return cached }

        let url = imagesDirectory.appendingPathComponent(filename)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgThumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let thumbnail = UIImage(cgImage: cgThumbnail)
        thumbnailCache.setObject(thumbnail, forKey: cacheKey)
        return thumbnail
    }

    static func delete(_ filename: String?) {
        guard let filename, !filename.isEmpty else { return }
        let url = imagesDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// The on-disk URL for a stored photo, for handing to the system share sheet so the
    /// original full-resolution image can be exported as its own file (not just embedded
    /// as a base64 PHOTO inside a vCard). Returns nil if there's no photo or the file is
    /// somehow missing.
    static func fileURL(for filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        let url = imagesDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
