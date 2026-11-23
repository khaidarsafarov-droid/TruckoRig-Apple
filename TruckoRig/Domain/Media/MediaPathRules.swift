import Foundation

/// Stored photo, scan, and receipt names stay inside one directory.
///
/// A name with a slash, a backslash, `..`, or a leading slash is refused. A relative path such
/// as `photos/name.jpg` is allowed only when every component is a plain file or folder name and
/// the resolved URL stays under `root`.
public enum MediaPathRules {
    public static func fileName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return nil }
        guard !trimmed.contains("/"), !trimmed.contains("\\") else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
        return trimmed
    }

    /// `nil` when `relative` is absolute, contains `..`, or would leave `root`.
    public static func url(relative: String, under root: URL) -> URL? {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("/"), !trimmed.contains(".."), !trimmed.contains("\\") else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { $0.value < 32 }) else { return nil }
        let parts = trimmed.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." && !$0.isEmpty }) else { return nil }
        var url = root
        for part in parts {
            url.appendPathComponent(part)
        }
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else { return nil }
        return url
    }
}
