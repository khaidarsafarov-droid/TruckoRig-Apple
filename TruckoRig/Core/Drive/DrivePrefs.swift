import Foundation

/// Android `GoogleDriveBackupPrefs` for the single `local_dev` journal.
///
/// Disconnect calls `clear()`, which drops the email and file id. `autoSyncEnabled` then falls
/// back to true, the same default SharedPreferences uses when the key is gone. The identity
/// alias map lives in a different store and survives disconnect.
final class DriveBackupPrefs {
    static let emailKey = "account_email"
    static let fileIDKey = "drive_file_id"
    static let autoSyncKey = "auto_sync"
    static let lastSyncKey = "last_sync_at"
    static let remoteModifiedKey = "remote_modified_at"
    static let lastErrorKey = "last_sync_error"
    static let lastErrorAtKey = "last_sync_error_at"

    let accountId: String
    private let defaults: UserDefaults
    private let suite: String

    init(accountId: String = DriveAccount.localDev, defaults: UserDefaults, suite: String) {
        self.accountId = accountId
        self.defaults = defaults
        self.suite = suite
    }

    static func standard(accountId: String = DriveAccount.localDev) -> DriveBackupPrefs {
        let suite = DriveAccount.prefsName(accountId: accountId)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let prefs = DriveBackupPrefs(accountId: accountId, defaults: defaults, suite: suite)
        prefs.migrateLegacyIfNeeded()
        return prefs
    }

    var accountEmail: String? {
        get { nonBlank(defaults.string(forKey: Self.emailKey)) }
        set { setOptional(Self.emailKey, newValue) }
    }

    var driveFileID: String? {
        get { nonBlank(defaults.string(forKey: Self.fileIDKey)) }
        set { setOptional(Self.fileIDKey, newValue) }
    }

    var autoSyncEnabled: Bool {
        get {
            guard defaults.object(forKey: Self.autoSyncKey) != nil else { return true }
            return defaults.bool(forKey: Self.autoSyncKey)
        }
        set { defaults.set(newValue, forKey: Self.autoSyncKey) }
    }

    var lastSyncAt: Int64 {
        get { number(Self.lastSyncKey) }
        set { defaults.set(NSNumber(value: newValue), forKey: Self.lastSyncKey) }
    }

    var remoteModifiedAt: Int64 {
        get { number(Self.remoteModifiedKey) }
        set { defaults.set(NSNumber(value: newValue), forKey: Self.remoteModifiedKey) }
    }

    var lastSyncError: String? {
        get { nonBlank(defaults.string(forKey: Self.lastErrorKey)) }
        set {
            if let newValue {
                let trimmed = String(newValue.prefix(DriveSchedule.maxErrorLength))
                defaults.set(trimmed, forKey: Self.lastErrorKey)
            } else {
                defaults.removeObject(forKey: Self.lastErrorKey)
            }
        }
    }

    var lastSyncErrorAt: Int64 {
        get { number(Self.lastErrorAtKey) }
        set { defaults.set(NSNumber(value: newValue), forKey: Self.lastSyncErrorAtKey) }
    }

    var isLinked: Bool { accountEmail != nil }

    var backupFileName: String { DriveAccount.backupFileName(accountId: accountId) }

    func clear() {
        defaults.removePersistentDomain(forName: suite)
    }

    func recordSuccess(fileID: String, remoteModifiedAt: Int64, now: Int64) {
        driveFileID = fileID
        self.remoteModifiedAt = remoteModifiedAt > 0 ? remoteModifiedAt : now
        lastSyncAt = now
        lastSyncError = nil
        lastSyncErrorAt = 0
    }

    func recordFailure(_ message: String, now: Int64) {
        lastSyncError = message
        lastSyncErrorAt = now
    }

    private func migrateLegacyIfNeeded() {
        let metaName = "truckerload_account_meta"
        let migratedKey = "legacy_drive_backup_migrated"
        guard defaults.string(forKey: Self.emailKey) == nil, defaults.string(forKey: Self.fileIDKey) == nil else {
            return
        }
        let meta = UserDefaults(suiteName: metaName) ?? .standard
        if meta.bool(forKey: migratedKey) { return }
        let legacy = UserDefaults(suiteName: "google_drive_backup") ?? .standard
        let legacyKeys = [Self.emailKey, Self.fileIDKey, Self.autoSyncKey, Self.lastSyncKey, Self.remoteModifiedKey]
        let hasLegacy = legacyKeys.contains { legacy.object(forKey: $0) != nil }
        if hasLegacy {
            if let email = legacy.string(forKey: Self.emailKey) { defaults.set(email, forKey: Self.emailKey) }
            if let fileID = legacy.string(forKey: Self.fileIDKey) { defaults.set(fileID, forKey: Self.fileIDKey) }
            if legacy.object(forKey: Self.autoSyncKey) != nil {
                defaults.set(legacy.bool(forKey: Self.autoSyncKey), forKey: Self.autoSyncKey)
            }
            if let last = legacy.object(forKey: Self.lastSyncKey) as? NSNumber {
                defaults.set(last, forKey: Self.lastSyncKey)
            }
            if let remote = legacy.object(forKey: Self.remoteModifiedKey) as? NSNumber {
                defaults.set(remote, forKey: Self.remoteModifiedKey)
            }
            legacy.removePersistentDomain(forName: "google_drive_backup")
        }
        meta.set(true, forKey: migratedKey)
    }

    private func number(_ key: String) -> Int64 {
        (defaults.object(forKey: key) as? NSNumber)?.int64Value ?? 0
    }

    private func setOptional(_ key: String, _ value: String?) {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
