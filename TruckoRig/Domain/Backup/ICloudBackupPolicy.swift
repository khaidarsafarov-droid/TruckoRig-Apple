import Foundation

/// iCloud Drive rules for the Android v2 JSON file. One file per account.
///
/// The periodic cadence and the 45-second debounce are `BackupSchedule`. Conflict choice is the
/// file's `exportedAt`: the newer snapshot wins. Replacing the journal on this phone with an
/// older copy, or with another account's file, waits for an explicit confirmation.
public enum ICloudBackupPolicy {
    public static let containerIdentifier = "iCloud.com.truckorig"
    public static let backgroundTaskIdentifier = "com.truckorig.icloud-sync"
    public static let originPlatformIOS = "ios"
    public static let originPlatformAndroid = "android"

    public static var periodicInterval: TimeInterval {
        TimeInterval(BackupSchedule.periodicIntervalSeconds)
    }

    public static var debounce: TimeInterval {
        TimeInterval(BackupSchedule.autoBackupDebounceSeconds)
    }

    public static var requiresNetwork: Bool { BackupSchedule.requiresNetwork }

    /// Stable name inside the ubiquity Documents folder. The bytes are a manual-export JSON file.
    public static func containerFileName(accountId: String) -> String {
        "\(BackupSchema.filePrefix)_Backup_\(BackupAccount.sanitizeFilePart(accountId)).json"
    }

    public enum Availability: Equatable, Sendable {
        case unknown
        case available
        case signedOut
        case containerMissing
    }

    public enum Resolution: Equatable, Sendable {
        /// This phone's journal is newer than the iCloud file, or iCloud has no file yet.
        case uploadLocal
        /// The iCloud file's `exportedAt` is newer. Leave that file alone.
        case keepRemote
        case inSync
    }

    /// Newer `exportedAt` wins.
    ///
    /// The local stamp is the newest load time on this phone, or the `exportedAt` of the last
    /// snapshot this phone uploaded — whichever is later. A missing remote file is an upload.
    public static func resolution(
        localNewestMillis: Int64,
        remoteExportedAt: Int64?,
        lastUploadedExportedAt: Int64
    ) -> Resolution {
        guard let remoteExportedAt, remoteExportedAt > 0 else { return .uploadLocal }
        let localStamp = max(localNewestMillis, lastUploadedExportedAt)
        if remoteExportedAt > localStamp { return .keepRemote }
        if localStamp > remoteExportedAt { return .uploadLocal }
        return .inSync
    }

    public struct VersionStamp: Equatable, Sendable {
        public var exportedAt: Int64
        public var isCurrent: Bool

        public init(exportedAt: Int64, isCurrent: Bool) {
            self.exportedAt = exportedAt
            self.isCurrent = isCurrent
        }
    }

    /// Index of the conflict copy that should remain. Ties keep the current file.
    public static func winningVersionIndex(_ versions: [VersionStamp]) -> Int? {
        guard !versions.isEmpty else { return nil }
        var best = 0
        for index in versions.indices.dropFirst() {
            let candidate = versions[index]
            let winner = versions[best]
            if candidate.exportedAt > winner.exportedAt {
                best = index
            } else if candidate.exportedAt == winner.exportedAt && candidate.isCurrent && !winner.isCurrent {
                best = index
            }
        }
        return best
    }

    public enum AutoSync: Equatable, Sendable {
        case upload
        case keepRemote
        case inSync
        case unavailable
        case autoOff
        case nothingToUpload
        case waitingForDebounce
    }

    public static func autoSync(
        availability: Availability,
        autoSyncEnabled: Bool,
        hasExportableContent: Bool,
        debounceElapsed: Bool,
        localNewestMillis: Int64,
        remoteExportedAt: Int64?,
        lastUploadedExportedAt: Int64
    ) -> AutoSync {
        if availability != .available { return .unavailable }
        if !autoSyncEnabled { return .autoOff }
        if !debounceElapsed { return .waitingForDebounce }
        if !hasExportableContent { return .nothingToUpload }
        switch resolution(
            localNewestMillis: localNewestMillis,
            remoteExportedAt: remoteExportedAt,
            lastUploadedExportedAt: lastUploadedExportedAt
        ) {
        case .uploadLocal: return .upload
        case .keepRemote: return .keepRemote
        case .inSync: return .inSync
        }
    }

    public enum ApplyBlock: Equatable, Sendable {
        case needsConfirmation
        case olderThanLocal
        case foreignAccount
        case unboundAccount
    }

    /// `nil` means the restore may replace the journal.
    ///
    /// Without confirmation nothing is applied. An older copy and a foreign account stay blocked
    /// until the driver confirms; they are not silent refusals and they are not silent writes.
    public static func applyBlock(
        confirmed: Bool,
        localNewestMillis: Int64,
        remoteExportedAt: Int64,
        fileAccountId: String?,
        activeAccountId: String
    ) -> ApplyBlock? {
        if confirmed { return nil }
        let account = fileAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let active = activeAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !account.isEmpty && !active.isEmpty && account != active { return .foreignAccount }
        if account.isEmpty { return .unboundAccount }
        if BackupSyncPolicy.shouldWarnBeforeFileRestore(
            localNewestMillis: localNewestMillis,
            backupExportedAt: remoteExportedAt
        ) {
            return .olderThanLocal
        }
        return .needsConfirmation
    }
}
