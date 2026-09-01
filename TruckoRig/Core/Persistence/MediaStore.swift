import Foundation
import ImageIO
import UIKit

/// On-disk storage for photos and scans.
///
/// Files live under the account's own directory and are referenced by name only: absolute paths
/// change between installs and iCloud restores, so storing them would produce dead references.
struct MediaStore {

    enum Kind: String {
        case photo
        case scan

        var directoryName: String {
            switch self {
            case .photo: return "Photos"
            case .scan: return "Scans"
            }
        }
    }

    let scope: AccountScope

    private var baseDirectory: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documents
            .appendingPathComponent("Media", isDirectory: true)
            .appendingPathComponent(scope.storeKey, isDirectory: true)
    }

    func directory(for kind: Kind) -> URL? {
        guard let base = baseDirectory else { return nil }
        let directory = base.appendingPathComponent(kind.directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func url(for fileName: String, kind: Kind) -> URL? {
        directory(for: kind)?.appendingPathComponent(fileName)
    }

    /// Writes a JPEG and returns its file name.
    ///
    /// Compressed to 0.8: cab photos of paperwork stay readable and a week of scans does not fill
    /// the phone.
    func save(_ image: UIImage, kind: Kind, quality: CGFloat = 0.8) throws -> String {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw MediaStoreError.encodingFailed
        }
        let fileName = "\(kind.rawValue)_\(UUID().uuidString).jpg"
        guard let url = url(for: fileName, kind: kind) else { throw MediaStoreError.directoryUnavailable }
        try data.write(to: url, options: .atomic)
        return fileName
    }

    func loadImage(named fileName: String, kind: Kind) -> UIImage? {
        guard let url = url(for: fileName, kind: kind) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Downsampled image for grid cells.
    ///
    /// Full-resolution photos in a grid are the fastest way to get the app jettisoned for memory,
    /// so thumbnails are decoded at the size actually drawn.
    func thumbnail(named fileName: String, kind: Kind, maxPixel: CGFloat = 300) -> UIImage? {
        guard let url = url(for: fileName, kind: kind),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    func delete(fileName: String, kind: Kind) {
        guard let url = url(for: fileName, kind: kind) else { return }
        try? FileManager.default.removeItem(at: url)
    }

}

enum MediaStoreError: Error, LocalizedError {
    case directoryUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable: return String(localized: "media.error.directory")
        case .encodingFailed: return String(localized: "media.error.encoding")
        }
    }
}
