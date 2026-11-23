import Foundation

/// Limits for a file a share sheet is allowed to copy.
///
/// The extension checks the size and the file header before it copies the file or opens it
/// as a PDF. The extension and the journal then keep at most `maxPages` pages and `maxText`
/// characters.
public enum ShareFileRules {
    public static let maxBytes = 20 * 1024 * 1024
    public static let maxPages = 30
    public static let maxText = 100_000
    /// Inbox rows older than this are deleted the next time the app or the extension runs.
    public static let staleInterval: TimeInterval = 7 * 24 * 60 * 60

    public static let allowedExtensions: Set<String> = ["pdf", "jpg", "jpeg", "png", "heic"]

    /// Extension to store, or nil when the header is not an allowed type.
    ///
    /// A known extension must match the header. An empty extension is filled in from the header.
    /// A different extension is refused even when the header looks valid.
    public static func storedExtension(pathExtension: String, header: Data) -> String? {
        let ext = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if accepts(extension: ext, header: header) { return ext == "jpeg" ? "jpg" : ext }
        guard ext.isEmpty else { return nil }
        if header.starts(with: Data("%PDF".utf8)) { return "pdf" }
        if header.starts(with: Data([0xFF, 0xD8, 0xFF])) { return "jpg" }
        if header.starts(with: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) { return "png" }
        if isHEIC(header) { return "heic" }
        return nil
    }

    public static func accepts(extension raw: String, header: Data) -> Bool {
        let ext = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard allowedExtensions.contains(ext) else { return false }
        switch ext {
        case "pdf":
            return header.starts(with: Data("%PDF".utf8))
        case "jpg", "jpeg":
            return header.starts(with: Data([0xFF, 0xD8, 0xFF]))
        case "png":
            return header.starts(with: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        case "heic":
            return isHEIC(header)
        default:
            return false
        }
    }

    /// ISO BMFF `ftyp` box. HEIC, HEIF, and the still-image brands iPhones write.
    private static func isHEIC(_ header: Data) -> Bool {
        guard header.count >= 12 else { return false }
        let brand = header.subdata(in: 4..<8)
        guard brand == Data("ftyp".utf8) else { return false }
        let major = String(data: header.subdata(in: 8..<12), encoding: .ascii)?.lowercased() ?? ""
        return ["heic", "heix", "mif1", "msf1"].contains(major)
    }
}
