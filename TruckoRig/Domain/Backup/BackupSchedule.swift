import Foundation

/// Cadence and size limits shared with Android auto-backup. Stage 2 reuses them for iCloud.
/// Android `BackupService` debounce is 45 seconds; `DriveSyncWorker` is 12 hours, network required.
public enum BackupSchedule {
    public static let periodicIntervalSeconds: Int64 = 12 * 60 * 60
    public static let autoBackupDebounceSeconds: Int64 = 45
    public static let requiresNetwork = true
    public static let requiresExternalPower = false
    public static let maxRestoreBytes = 32 * 1024 * 1024
    /// Stored sync errors are truncated the same way Android prefs truncate them.
    public static let maxErrorLength = 240

    public enum AutoPush: Equatable, Sendable {
        /// Nothing to do. Android returns success.
        case skip
        /// List failed. Android returns false so WorkManager retries. A failed list is not "no file".
        case metadataUnavailable
        case upload
    }

    public static func autoPush(
        clientConfigured: Bool,
        autoSyncEnabled: Bool,
        isLinked: Bool,
        scopeGranted: Bool,
        remoteProbeFailed: Bool,
        remoteExists: Bool,
        remoteModifiedAt: Int64,
        lastSyncAt: Int64,
        hasExportableContent: Bool
    ) -> AutoPush {
        if !clientConfigured || !autoSyncEnabled || (!isLinked && !scopeGranted) {
            return .skip
        }
        if remoteProbeFailed { return .metadataUnavailable }
        if remoteExists && BackupSyncPolicy.shouldSkipAutoPush(
            remoteModifiedAt: remoteModifiedAt,
            lastSyncAt: lastSyncAt
        ) {
            return .skip
        }
        if !hasExportableContent { return .skip }
        return .upload
    }

    public enum PeriodicResult: Equatable, Sendable {
        case success
        case retry
    }

    /// Blank account: success and do nothing. A failed push asks the scheduler to retry.
    public static func periodicResult(userId: String?, pushSucceeded: Bool) -> PeriodicResult {
        if !BackupSyncEligibility.shouldEnqueuePeriodic(userId: userId) { return .success }
        return pushSucceeded ? .success : .retry
    }
}
