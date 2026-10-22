import Foundation

/// Android `AccountIds` for the single on-device journal.
///
/// New Android installs use `local_dev`. The Drive file name is derived from that id so an
/// iOS backup lands in the same app-data file a local Android install would write.
public enum DriveAccount {
    public static let localDev = "local_dev"
    public static let legacyFileName = "truckerload_backup.tlb"

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

    /// Android `GoogleDriveBackupPrefs.backupFileName`.
    public static func backupFileName(accountId: String) -> String {
        "truckerload_backup_\(sanitizeFilePart(accountId)).tlb"
    }

    /// Android prefs file `google_drive_backup_<account>`.
    public static func prefsName(accountId: String) -> String {
        "google_drive_backup_\(sanitizeFilePart(accountId))"
    }
}
