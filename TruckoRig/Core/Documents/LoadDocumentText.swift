import Compression
import Foundation
import PDFKit

enum LoadDocumentError: Error {
    case unreadable
    case empty
}

/// Text from a PDF, Word, Excel or plain-text file the driver picked in Files.
enum LoadDocumentText {
    static func read(url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let text: String
        switch ext {
        case "pdf":
            text = PDFDocument(data: data)?.string ?? ""
        case "docx", "xlsx":
            text = try officeText(data)
        default:
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LoadDocumentError.empty }
        return trimmed
    }

    private static func officeText(_ data: Data) throws -> String {
        let files = try ZipArchive.entries(in: data)
        let xml = files.first { $0.name == "word/document.xml" }?.text
            ?? files.first { $0.name == "xl/sharedStrings.xml" }?.text
            ?? ""
        return OfficeXMLText.plainText(xml: xml)
    }
}

/// Reads stored and deflated files out of a docx/xlsx zip. Enough for Office Open XML, not a general unzip.
enum ZipArchive {
    struct Entry {
        var name: String
        var text: String
    }

    static func entries(in data: Data) throws -> [Entry] {
        let bytes = [UInt8](data)
        guard let eocd = endOfCentralDirectory(bytes) else { throw LoadDocumentError.unreadable }
        var offset = eocd
        var found: [Entry] = []
        while offset + 46 <= bytes.count, u32(bytes, offset) == 0x02014b50 {
            let method = u16(bytes, offset + 10)
            let compressed = Int(u32(bytes, offset + 20))
            let nameLength = Int(u16(bytes, offset + 28))
            let extra = Int(u16(bytes, offset + 30))
            let comment = Int(u16(bytes, offset + 32))
            let local = Int(u32(bytes, offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { break }
            let name = String(bytes: bytes[nameStart..<(nameStart + nameLength)], encoding: .utf8) ?? ""
            if let payload = inflateLocal(bytes, localHeader: local, method: method, compressedSize: compressed),
               let text = String(data: payload, encoding: .utf8) {
                found.append(Entry(name: name, text: text))
            }
            offset = nameStart + nameLength + extra + comment
        }
        return found
    }

    private static func inflateLocal(_ bytes: [UInt8], localHeader: Int, method: Int, compressedSize: Int) -> Data? {
        guard localHeader + 30 <= bytes.count, u32(bytes, localHeader) == 0x04034b50 else { return nil }
        let nameLength = Int(u16(bytes, localHeader + 26))
        let extra = Int(u16(bytes, localHeader + 28))
        let start = localHeader + 30 + nameLength + extra
        guard start + compressedSize <= bytes.count else { return nil }
        let slice = Data(bytes[start..<(start + compressedSize)])
        if method == 0 { return slice }
        guard method == 8 else { return nil }
        return inflate(slice)
    }

    private static func inflate(_ data: Data) -> Data? {
        var wrapped = Data([0x78, 0x9C])
        wrapped.append(data)
        let destinationSize = max(data.count * 8, 65_536)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }
        let written = wrapped.withUnsafeBytes { raw -> Int in
            guard let source = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(destination, destinationSize, source, wrapped.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        return Data(bytes: destination, count: written)
    }

    private static func endOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let start = max(0, bytes.count - 65_557)
        var index = bytes.count - 22
        while index >= start {
            if u32(bytes, index) == 0x06054b50 { return Int(u32(bytes, index + 16)) }
            index -= 1
        }
        return nil
    }

    private static func u16(_ bytes: [UInt8], _ index: Int) -> UInt16 {
        UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
    }

    private static func u32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(u16(bytes, index)) | (UInt32(u16(bytes, index + 2)) << 16)
    }
}
