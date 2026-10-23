import Foundation

/// Turns a user-selected backup file into JSON text. Android `BackupRestoreParser`.
public enum BackupParseFailure: Error, Equatable, Sendable {
    case invalidFormat
    case chartNote
}

public enum BackupRestoreParser {
    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let hiddenSeparator: Character = "\u{1E}"
    private static let legacyBegin = "-----BEGIN TRUCKERLOAD BACKUP-----"
    private static let legacyEnd = "-----END TRUCKERLOAD BACKUP-----"

    public static func parseToJSON(_ bytes: Data) throws -> String {
        let stripped = stripUTF8BOM(bytes)
        if stripped.isEmpty { throw BackupParseFailure.invalidFormat }
        if let extracted = extractBackupJSON(stripped) {
            let text = BackupJSON.stripBOM(extracted).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { throw BackupParseFailure.invalidFormat }
            return text
        }
        let text = String(decoding: stripped, as: UTF8.self)
        if looksLikeChartNote(text) { throw BackupParseFailure.chartNote }
        throw BackupParseFailure.invalidFormat
    }

    public static func stripUTF8BOM(_ bytes: Data) -> Data {
        guard bytes.count >= 3,
              bytes[bytes.startIndex] == utf8BOM[0],
              bytes[bytes.startIndex + 1] == utf8BOM[1],
              bytes[bytes.startIndex + 2] == utf8BOM[2]
        else { return bytes }
        return bytes.dropFirst(3)
    }

    static func looksLikeChartNote(_ text: String) -> Bool {
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        if first.hasPrefix("{") || first.hasPrefix("[") { return false }
        if first.range(of: "BEGIN TRUCKERLOAD BACKUP", options: String.CompareOptions.caseInsensitive) != nil { return false }
        if first.hasPrefix("TL1:") { return false }
        return first.split(separator: " | ").count >= 3
    }

    private static func extractBackupJSON(_ bytes: Data) -> String? {
        if let nullIndex = bytes.firstIndex(of: 0), nullIndex < bytes.index(before: bytes.endIndex) {
            let rest = bytes[(bytes.index(after: nullIndex))...]
            let text = String(decoding: rest, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("{") { return text }
        }
        return extractBackupJSON(String(decoding: bytes, as: UTF8.self))
    }

    private static func extractBackupJSON(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") { return trimmed }

        if let separator = content.firstIndex(of: hiddenSeparator) {
            let payload = String(content[content.index(after: separator)...])
            if let json = decodeBase64(payload) { return json }
        }

        let legacy = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("TL1:") }
        if let legacy, let json = decodeBase64(String(legacy.dropFirst(4))) {
            return json
        }

        if let start = content.range(of: legacyBegin),
           let end = content.range(of: legacyEnd),
           start.upperBound <= end.lowerBound {
            return String(content[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func decodeBase64(_ encoded: String) -> String? {
        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
