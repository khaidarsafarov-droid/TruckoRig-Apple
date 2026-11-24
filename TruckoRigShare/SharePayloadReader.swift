import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// One attachment, already copied out of the provider's temporary URL.
struct SharePiece: Sendable {
    var text: String
    var fileBytes: Data?
    var fileName: String?
    var pageCount: Int
}

/// Reads share-sheet items on device. OCR is capped so the extension stays under its memory limit.
enum SharePayloadReader {
    static let maxAttachments = 8
    static let maxOCRPages = 3
    static let maxImageEdge = 1600
    static let maxOCRBytes = ShareFileRules.maxBytes
    static let textLimit = ShareFileRules.maxText

    static func pieces(from context: NSExtensionContext?) async -> [SharePiece] {
        let items = context?.inputItems as? [NSExtensionItem] ?? []
        var pieces: [SharePiece] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if pieces.count >= maxAttachments { return pieces }
                if let piece = await read(provider) {
                    pieces.append(piece)
                }
            }
        }
        return pieces
    }

    private static func read(_ provider: NSItemProvider) async -> SharePiece? {
        var texts: [String] = []
        var fileBytes: Data?
        var fileName: String?
        var pageCount = 0

        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            if let file = try? await readFile(provider, type: UTType.pdf.identifier) {
                fileBytes = file.bytes
                fileName = file.name
                let pdf = await pdfText(file.bytes)
                pageCount = pdf.pages
                if !pdf.text.isEmpty { texts.append(pdf.text) }
            }
        }

        if fileBytes == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let file = try? await readFile(provider, type: UTType.image.identifier) {
                fileBytes = file.bytes
                fileName = file.name
                pageCount = 1
                if let text = await ocrImage(file.bytes), !text.isEmpty { texts.append(text) }
            }
        }

        if let text = await loadText(provider), !text.isEmpty {
            texts.append(text)
        }

        if texts.isEmpty, let url = await loadURL(provider) {
            texts.append(url.absoluteString)
            if fileName == nil { fileName = url.lastPathComponent }
        }

        if fileBytes == nil, provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let file = try? await readFile(provider, type: UTType.fileURL.identifier) {
                fileBytes = file.bytes
                fileName = file.name
                if let text = textFromBytes(file.bytes, name: file.name), !text.isEmpty {
                    texts.append(text)
                }
            }
        }

        let joined = texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty || fileBytes != nil else { return nil }
        return SharePiece(
            text: String(joined.prefix(textLimit)),
            fileBytes: fileBytes,
            fileName: fileName,
            pageCount: pageCount
        )
    }

    static func pdfText(_ bytes: Data) async -> (text: String, pages: Int) {
        guard bytes.count <= ShareFileRules.maxBytes else { return ("", 0) }
        guard let document = PDFDocument(data: bytes) else { return ("", 0) }
        let pages = min(document.pageCount, ShareFileRules.maxPages)
        var parts: [String] = []
        for index in 0..<pages {
            guard let page = document.page(at: index), let text = page.string, !text.isEmpty else { continue }
            parts.append(text)
        }
        let layer = String(parts.joined(separator: "\n\n").prefix(textLimit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if layer.count >= 40 || bytes.count > maxOCRBytes { return (layer, pages) }
        var recognized: [String] = []
        let cap = min(pages, maxOCRPages)
        for index in 0..<cap {
            guard let page = document.page(at: index) else { continue }
            let image = page.thumbnail(of: CGSize(width: 1200, height: 1600), for: .mediaBox)
            if let text = await OCRService.recognizeText(in: image)?.text, !text.isEmpty {
                recognized.append(text)
            }
        }
        let ocr = recognized.joined(separator: "\n\n")
        return (ocr.isEmpty ? layer : ocr, pages)
    }

    private static func ocrImage(_ bytes: Data) async -> String? {
        guard bytes.count <= maxOCRBytes, let image = thumbnail(bytes, maxPixel: maxImageEdge) else { return nil }
        return await OCRService.recognizeText(in: image)?.text
    }

    private static func thumbnail(_ bytes: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func readCappedText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: textLimit)
        return String(data: data, encoding: .utf8)
    }

    private static func textFromBytes(_ bytes: Data, name: String) -> String? {
        if name.lowercased().hasSuffix("pdf") {
            return nil
        }
        return String(data: bytes.prefix(textLimit), encoding: .utf8)
    }

    private static func byteCount(_ url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else { return nil }
        if values.isDirectory == true { return nil }
        return values.fileSize
    }

    private struct SharedFile {
        var bytes: Data
        var name: String
    }

    /// Size and header check used by the share sheet. A mismatched image is refused before OCR.
    static func storedFile(at url: URL) throws -> (bytes: Data, name: String) {
        guard let size = byteCount(url), size <= ShareFileRules.maxBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(size)
        while buffer.count < size {
            let chunk = handle.readData(ofLength: min(1024 * 1024, size - buffer.count))
            if chunk.isEmpty { break }
            buffer.append(chunk)
        }
        let header = Data(buffer.prefix(32))
        guard buffer.count == size,
              let ext = ShareFileRules.storedExtension(pathExtension: url.pathExtension, header: header)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let name = url.pathExtension.isEmpty ? "attachment." + ext : url.lastPathComponent
        return (buffer, name)
    }

    /// One buffer: the provider file is read once, checked, and that buffer is what gets sealed.
    private static func readFile(_ provider: NSItemProvider, type: String) async throws -> SharedFile {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: CocoaError(.fileReadNoSuchFile))
                    return
                }
                do {
                    let file = try storedFile(at: url)
                    continuation.resume(returning: SharedFile(bytes: file.bytes, name: file.name))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        let types = [UTType.plainText.identifier, UTType.utf8PlainText.identifier, UTType.text.identifier]
        for type in types where provider.hasItemConformingToTypeIdentifier(type) {
            guard let item = try? await loadItem(provider, type: type) else { continue }
            if let text = item as? String, !text.isEmpty { return String(text.prefix(textLimit)) }
            if let data = item as? Data, let text = String(data: data.prefix(textLimit), encoding: .utf8), !text.isEmpty {
                return text
            }
            if let url = item as? URL, let text = readCappedText(url), !text.isEmpty { return text }
        }
        return nil
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        guard let item = try? await loadItem(provider, type: UTType.url.identifier) else { return nil }
        return item as? URL
    }

    private static func loadItem(_ provider: NSItemProvider, type: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: item)
            }
        }
    }
}
