import Foundation
import ImageIO
import UIKit

/// On-disk storage for photos and scans.
///
/// Android keeps files in `getExternalFilesDir()/photos` and `.../scans` and stores the absolute
/// path. Here the same folder names live under the account directory, and the database stores the
/// relative path (`photos/name.jpg`) because the iOS container path is not stable.
struct MediaStore {

    enum Kind: String {
        case photo
        case scan

        var directoryName: String {
            switch self {
            case .photo: return PhotoCapture.directoryName
            case .scan: return ScanCapture.directoryName
            }
        }

        /// Folder used before this stage renamed storage to the Android names.
        var legacyDirectoryName: String {
            switch self {
            case .photo: return "Photos"
            case .scan: return "Scans"
            }
        }
    }

    let root: URL

    init(scope: AccountScope, root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.root = documents
                .appendingPathComponent("Media", isDirectory: true)
                .appendingPathComponent(scope.storeKey, isDirectory: true)
        }
    }

    func directory(for kind: Kind) -> URL {
        let directory = root.appendingPathComponent(kind.directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func url(for fileName: String, kind: Kind) -> URL {
        directory(for: kind).appendingPathComponent(fileName)
    }

    /// Resolves a stored relative path, then the legacy `Photos`/`Scans` folders.
    func existingFile(fileName: String, filePath: String?, kind: Kind) -> URL? {
        if let filePath, !filePath.isEmpty {
            if filePath.hasPrefix("/") {
                let absolute = URL(fileURLWithPath: filePath)
                if FileManager.default.fileExists(atPath: absolute.path) { return absolute }
            } else {
                let relative = root.appendingPathComponent(filePath)
                if FileManager.default.fileExists(atPath: relative.path) { return relative }
            }
        }
        let current = url(for: fileName, kind: kind)
        if FileManager.default.fileExists(atPath: current.path) { return current }
        let legacy = root
            .appendingPathComponent(kind.legacyDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: legacy.path) { return legacy }
        return nil
    }

    func write(_ data: Data, fileName: String, kind: Kind) throws -> URL {
        guard !data.isEmpty else { throw MediaStoreError.encodingFailed }
        let url = url(for: fileName, kind: kind)
        try data.write(to: url, options: .atomic)
        return url
    }

    func loadImage(named fileName: String, filePath: String? = nil, kind: Kind) -> UIImage? {
        guard let url = existingFile(fileName: fileName, filePath: filePath, kind: kind) else { return nil }
        if kind == .scan || url.pathExtension.lowercased() == "pdf" {
            return ScanPDFWriter.firstPageImage(at: url)
        }
        return UIImage(contentsOfFile: url.path)
    }

    func thumbnail(named fileName: String, filePath: String? = nil, kind: Kind, maxPixel: CGFloat = 300) -> UIImage? {
        guard let url = existingFile(fileName: fileName, filePath: filePath, kind: kind),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return loadImage(named: fileName, filePath: filePath, kind: kind)
        }
        return UIImage(cgImage: cgImage)
    }

    static let receiptsDirectoryName = "receipts"

    /// Copies receipt bytes with no load watermark. Returns `receipts/<file>`.
    func writeReceipt(data: Data, fileName: String) throws -> String {
        guard !data.isEmpty else { throw MediaStoreError.encodingFailed }
        let directory = root.appendingPathComponent(Self.receiptsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return "\(Self.receiptsDirectoryName)/\(fileName)"
    }

    func receiptFile(relativePath: String) -> URL? {
        guard !relativePath.isEmpty else { return nil }
        let url = relativePath.hasPrefix("/")
            ? URL(fileURLWithPath: relativePath)
            : root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func receiptImage(relativePath: String) -> UIImage? {
        guard let url = receiptFile(relativePath: relativePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func deleteReceipt(relativePath: String) {
        guard let url = receiptFile(relativePath: relativePath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func delete(fileName: String, filePath: String? = nil, kind: Kind) {
        if let url = existingFile(fileName: fileName, filePath: filePath, kind: kind) {
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: url(for: fileName, kind: kind))
    }

    /// PDF files in `scans/` that no row references. Called when the scan gallery opens.
    func cleanupOrphanScans(knownRelativePaths: Set<String>) -> Int {
        let directory = directory(for: .scan)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        let orphans = OrphanScanCleanup.unreferenced(fileNames: names, knownRelativePaths: knownRelativePaths)
        var removed = 0
        for name in orphans {
            let url = directory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
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
