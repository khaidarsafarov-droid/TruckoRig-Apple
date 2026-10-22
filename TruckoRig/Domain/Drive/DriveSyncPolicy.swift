import Foundation

/// Android `DriveSyncPolicy`. Retry and conflict rules with no Drive SDK.
public enum DriveSyncPolicy {
    public static let defaultMaxAttempts = 3
    public static let defaultBaseDelayMs: Int64 = 400
    /// Ignore tiny clock skew when comparing remote modifiedTime vs last sync.
    public static let defaultSkewMs: Int64 = 2_000

    public static func backoffDelayMs(attemptIndex: Int, baseDelayMs: Int64 = defaultBaseDelayMs) -> Int64 {
        baseDelayMs * Int64(max(attemptIndex + 1, 1))
    }

    public static func isRetryableFailure(_ message: String?) -> Bool {
        let text = (message ?? "").lowercased()
        if text.contains("not signed") || text.contains("consent") || text.contains("401") {
            return false
        }
        return text.contains("timeout")
            || text.contains("503")
            || text.contains("429")
            || text.contains("500")
            || text.contains("502")
            || text.contains("connection")
            || text.contains("unable to resolve")
            || text.contains("failed")
    }

    /// Warn before restore when this device has unsynced edits and Drive is newer than the last push.
    public static func shouldWarnBeforeRestore(
        localChangedAfterLastSync: Bool,
        remoteModifiedAt: Int64,
        lastSyncAt: Int64,
        skewMs: Int64 = defaultSkewMs
    ) -> Bool {
        if !localChangedAfterLastSync { return false }
        if lastSyncAt <= 0 || remoteModifiedAt <= 0 { return localChangedAfterLastSync }
        return remoteModifiedAt > lastSyncAt + skewMs
    }

    public static func remoteIsNewer(
        remoteModifiedAt: Int64,
        lastSyncAt: Int64,
        skewMs: Int64 = defaultSkewMs
    ) -> Bool {
        remoteModifiedAt > 0 && lastSyncAt > 0 && remoteModifiedAt > lastSyncAt + skewMs
    }

    /// Skip a background upload when this device has never synced but Drive already has a file,
    /// or when the remote file is newer than the last push.
    public static func shouldSkipAutoPush(
        remoteModifiedAt: Int64,
        lastSyncAt: Int64,
        skewMs: Int64 = defaultSkewMs
    ) -> Bool {
        if remoteModifiedAt <= 0 { return false }
        if lastSyncAt <= 0 { return true }
        return remoteIsNewer(remoteModifiedAt: remoteModifiedAt, lastSyncAt: lastSyncAt, skewMs: skewMs)
    }

    /// Android only looks at loads. An empty journal with no successful sync counts as dirty.
    public static func hasLocalChangesAfterLastSync(
        updatedAt: [Int64],
        parsedAt: [Int64],
        lastSyncAt: Int64
    ) -> Bool {
        if lastSyncAt <= 0 { return !updatedAt.isEmpty }
        for index in updatedAt.indices {
            let parsed = index < parsedAt.count ? parsedAt[index] : 0
            if updatedAt[index] > lastSyncAt || parsed > lastSyncAt { return true }
        }
        return false
    }
}

/// Android `DriveSyncEligibility`. Any non-blank account, including `local_dev`, may schedule.
public enum DriveSyncEligibility {
    public static func shouldEnqueuePeriodic(userId: String?) -> Bool {
        guard let userId else { return false }
        return !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
