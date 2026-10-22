import Foundation

/// Android `AccountIds` for the single on-device journal.
///
/// New Android installs use `local_dev`. File backups write that id so a local Android
/// install accepts the JSON, and this phone refuses a file tied to a different account.
public enum BackupAccount {
    public static let localDev = "local_dev"

    /// Android `AccountIds.sanitizeFilePart`: trim, replace anything outside `[A-Za-z0-9_-]`,
    /// keep 80 characters, fall back to `unknown`.
    public static func sanitizeFilePart(_ userId: String) -> String {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleaned = ""
        cleaned.reserveCapacity(trimmed.count)
        for scalar in trimmed.unicodeScalars {
            let value = scalar.value
            let allowed = (value >= 48 && value <= 57)
                || (value >= 65 && value <= 90)
                || (value >= 97 && value <= 122)
                || scalar == "-"
                || scalar == "_"
            cleaned.append(allowed ? Character(scalar) : "_")
        }
        if cleaned.isEmpty { return "unknown" }
        if cleaned.count > 80 { return String(cleaned.prefix(80)) }
        return cleaned
    }

    /// On-device map of Android integer ids. Not part of the JSON file.
    public static func identitySuiteName(accountId: String) -> String {
        "truckorig.backup.\(sanitizeFilePart(accountId)).identity"
    }
}
