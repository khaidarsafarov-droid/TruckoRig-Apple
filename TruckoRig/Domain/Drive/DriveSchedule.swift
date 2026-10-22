import Foundation

/// When a Drive upload is allowed to run. Android `GoogleDriveBackupService.pushAutoBackupIfEnabled`
/// plus `DriveSyncWorker` (12 hours, network required).
public enum DriveSchedule {
    public static let periodicIntervalSeconds: Int64 = 12 * 60 * 60
    public static let autoBackupDebounceSeconds: Int64 = 45
    public static let requiresNetwork = true
    public static let requiresExternalPower = false
    public static let taskIdentifier = "com.truckorig.drive-sync"
    /// The only Drive scope. Identity scopes come from the sign-in SDK the same way
    /// Android `DEFAULT_SIGN_IN` + `requestEmail` does.
    public static let driveAppDataScope = "https://www.googleapis.com/auth/drive.appdata"
    public static let maxRestoreBytes = 32 * 1024 * 1024
    /// Android `GoogleDriveBackupPrefs` truncates the stored error.
    public static let maxErrorLength = 240

    public static let placeholderClientMarker = "REPLACE_WITH_IOS_OAUTH_CLIENT_ID"

    /// A real iOS OAuth client id. The placeholder and a blank value keep backup off,
    /// the same way Android stays off when `GOOGLE_DRIVE_API_KEY` is blank.
    public static func validatedClientID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(placeholderClientMarker) else { return nil }
        guard trimmed.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return trimmed
    }

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
        if remoteExists && DriveSyncPolicy.shouldSkipAutoPush(
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
        if !DriveSyncEligibility.shouldEnqueuePeriodic(userId: userId) { return .success }
        return pushSucceeded ? .success : .retry
    }
}
