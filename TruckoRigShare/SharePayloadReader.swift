import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// One attachment, already copied out of the provider's temporary URL.
struct SharePiece: Sendable {
    var text: String
    var fileURL: URL?
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
        var fileURL: URL?
        var fileName: String?
        var pageCount = 0

        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            if let url = try? await copyFile(provider, type: UTType.pdf.identifier) {
                fileURL = url
                fileName = url.lastPathComponent
                let pdf = await pdfText(at: url)
                pageCount = pdf.pages
                if !pdf.text.isEmpty { texts.append(pdf.text) }
            }
        }

        if fileURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let url = try? await copyFile(provider, type: UTType.image.identifier) {
                fileURL = url
                fileName = url.lastPathComponent
                pageCount = 1
                if let text = await ocrImage(at: url), !text.isEmpty { texts.append(text) }
            }
        }

        if let text = await loadText(provider), !text.isEmpty {
            texts.append(text)
        }

        if texts.isEmpty, let url = await loadURL(provider) {
            texts.append(url.absoluteString)
            if fileName == nil { fileName = url.lastPathComponent }
        }

        if fileURL == nil, provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = try? await copyFile(provider, type: UTType.fileURL.identifier) {
                fileURL = url
                fileName = url.lastPathComponent
                if let text = try? LoadDocumentText.read(url: url), !text.isEmpty {
                    texts.append(text)
                }
            }
        }

        let joined = texts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty || fileURL != nil else { return nil }
        return SharePiece(
            text: String(joined.prefix(textLimit)),
            fileURL: fileURL,
            fileName: fileName,
            pageCount: pageCount
        )
    }

    private static func pdfText(at url: URL) async -> (text: String, pages: Int) {
        guard fileSize(url) <= ShareFileRules.maxBytes else { return ("", 0) }
        guard let document = PDFDocument(url: url) else { return ("", 0) }
        let pages = min(document.pageCount, ShareFileRules.maxPages)
        var parts: [String] = []
        for index in 0..<pages {
            guard let page = document.page(at: index), let text = page.string, !text.isEmpty else { continue }
            parts.append(text)
        }
        let layer = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if layer.count >= 40 || fileSize(url) > maxOCRBytes { return (layer, pages) }
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

    private static func ocrImage(at url: URL) async -> String? {
        guard fileSize(url) <= maxOCRBytes, let image = thumbnail(url: url, maxPixel: maxImageEdge) else { return nil }
        return await OCRService.recognizeText(in: image)?.text
    }

    private static func thumbnail(url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func headerBytes(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return handle.readData(ofLength: 32)
    }

    private static func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        let types = [UTType.plainText.identifier, UTType.utf8PlainText.identifier, UTType.text.identifier]
        for type in types where provider.hasItemConformingToTypeIdentifier(type) {
            guard let item = try? await loadItem(provider, type: type) else { continue }
            if let text = item as? String, !text.isEmpty { return text }
            if let data = item as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty { return text }
            if let url = item as? URL, let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty { return text }
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

    private static func copyFile(_ provider: NSItemProvider, type: String) async throws -> URL {
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
                    let header = try headerBytes(url)
                    guard fileSize(url) <= ShareFileRules.maxBytes,
                          let ext = ShareFileRules.storedExtension(pathExtension: url.pathExtension, header: header)
                    else {
                        continuation.resume(throwing: CocoaError(.fileReadCorruptFile))
                        return
                    }
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
