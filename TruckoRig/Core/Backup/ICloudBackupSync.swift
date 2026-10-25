import Foundation

/// Last upload time for one on-device account. Not part of the JSON file.
final class ICloudBackupPrefs {
    private let defaults: UserDefaults
    private let autoKey = "autoSync"
    private let uploadedKey = "lastUploadedExportedAt"
    private let syncKey = "lastSyncAt"
    private let errorKey = "lastError"
    private let mediaKey = "mediaEnabled"
    private let wifiKey = "wifiOnly"
    private let mediaSyncKey = "lastMediaUploadAt"
    private let mediaBytesKey = "lastMediaBytes"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func standard(accountId: String = BackupAccount.localDev) -> ICloudBackupPrefs {
        let name = "truckorig.icloud.\(BackupAccount.sanitizeFilePart(accountId))"
        return ICloudBackupPrefs(defaults: UserDefaults(suiteName: name) ?? .standard)
    }

    var autoSyncEnabled: Bool {
        get {
            if defaults.object(forKey: autoKey) == nil { return true }
            return defaults.bool(forKey: autoKey)
        }
        set { defaults.set(newValue, forKey: autoKey) }
    }

    var lastUploadedExportedAt: Int64 {
        get { read(uploadedKey) }
        set { write(uploadedKey, newValue) }
    }

    var lastSyncAt: Int64 {
        get { read(syncKey) }
        set { write(syncKey, newValue) }
    }

    var mediaEnabled: Bool {
        get {
            if defaults.object(forKey: mediaKey) == nil { return ICloudMediaPolicy.mediaEnabledByDefault }
            return defaults.bool(forKey: mediaKey)
        }
        set { defaults.set(newValue, forKey: mediaKey) }
    }

    var wifiOnly: Bool {
        get {
            if defaults.object(forKey: wifiKey) == nil { return ICloudMediaPolicy.wifiOnlyByDefault }
            return defaults.bool(forKey: wifiKey)
        }
        set { defaults.set(newValue, forKey: wifiKey) }
    }

    var lastMediaUploadAt: Int64 {
        get { read(mediaSyncKey) }
        set { write(mediaSyncKey, newValue) }
    }

    var lastMediaBytes: Int64 {
        get { read(mediaBytesKey) }
        set { write(mediaBytesKey, newValue) }
    }

    var lastError: String? {
        get { defaults.string(forKey: errorKey) }
        set {
            if let newValue {
                defaults.set(String(newValue.prefix(BackupSchedule.maxErrorLength)), forKey: errorKey)
            } else {
                defaults.removeObject(forKey: errorKey)
            }
        }
    }

    private func read(_ key: String) -> Int64 {
        (defaults.object(forKey: key) as? NSNumber)?.int64Value ?? 0
    }

    private func write(_ key: String, _ value: Int64) {
        defaults.set(NSNumber(value: value), forKey: key)
    }
}

struct ICloudRemoteSnapshot: Equatable, Sendable {
    var json: String
    var exportedAt: Int64
    var accountId: String?
    var originDevice: String?
    var originPlatform: String?
    var accountMismatch: Bool
    var unbound: Bool
}

enum ICloudSyncOutcome: Error, Equatable, Sendable {
    case uploaded(Int64)
    case keepRemote(Int64)
    case inSync
    case unavailable
    case autoOff
    case nothingToUpload
    case waitingForDebounce
    case metadataUnavailable
    case notDownloaded
    case remoteSchemaTooNew(Int)
    case failed
    case refusedSecret
}

struct ICloudSyncRequest: Equatable, Sendable {
    var accountId: String
    var localNewestMillis: Int64
    var hasExportableContent: Bool
    var payload: Data?
    var debounceElapsed: Bool
    var autoSyncEnabled: Bool
    /// Manual "Sync now" still runs when automatic sync is off.
    var respectsAutoSwitch: Bool
    var now: Int64
}

/// Decides and performs one iCloud pass. It never replaces the on-device journal.
final class ICloudSyncEngine {
    let store: ICloudDriveStore
    let prefs: ICloudBackupPrefs

    init(store: ICloudDriveStore, prefs: ICloudBackupPrefs) {
        self.store = store
        self.prefs = prefs
    }

    func perform(_ request: ICloudSyncRequest) -> ICloudSyncOutcome {
        let availability = store.availability()
        let autoSyncEnabled = request.respectsAutoSwitch ? request.autoSyncEnabled : true
        let decision = ICloudBackupPolicy.autoSync(
            availability: availability,
            autoSyncEnabled: autoSyncEnabled,
            hasExportableContent: request.hasExportableContent,
            debounceElapsed: request.debounceElapsed,
            localNewestMillis: request.localNewestMillis,
            remoteExportedAt: nil,
            lastUploadedExportedAt: prefs.lastUploadedExportedAt
        )
        if decision == .unavailable { return .unavailable }
        if decision == .autoOff { return .autoOff }
        if decision == .waitingForDebounce { return .waitingForDebounce }
        if decision == .nothingToUpload { return .nothingToUpload }

        let remote: BackupData?
        switch readRemote(accountId: request.accountId) {
        case .missing:
            remote = nil
        case .snapshot(let backup, _):
            remote = backup
        case .notDownloaded:
            return .notDownloaded
        case .schemaTooNew(let version):
            return .remoteSchemaTooNew(version)
        case .unavailable:
            return .unavailable
        case .unreadable:
            prefs.lastError = "icloud_metadata_unavailable"
            return .metadataUnavailable
        }

        let action = ICloudBackupPolicy.autoSync(
            availability: .available,
            autoSyncEnabled: autoSyncEnabled,
            hasExportableContent: request.hasExportableContent,
            debounceElapsed: true,
            localNewestMillis: request.localNewestMillis,
            remoteExportedAt: remote?.exportedAt,
            lastUploadedExportedAt: prefs.lastUploadedExportedAt
        )
        switch action {
        case .upload:
            guard let payload = request.payload else { return .nothingToUpload }
            if ICloudMediaPolicy.documentIsSecret(Array(payload)) {
                prefs.lastError = "icloud_secret_refused"
                return .refusedSecret
            }
            do {
                try store.write(payload, accountId: request.accountId)
            } catch ICloudDriveStore.Failure.refusedSecret {
                prefs.lastError = "icloud_secret_refused"
                return .refusedSecret
            } catch {
                prefs.lastError = "icloud_write_failed"
                return .failed
            }
            let exportedAt = (try? BackupDataCodec.decode(Self.text(payload)))?.exportedAt ?? request.now
            prefs.lastUploadedExportedAt = exportedAt
            prefs.lastSyncAt = request.now
            prefs.lastError = nil
            return .uploaded(exportedAt)
        case .keepRemote:
            return .keepRemote(remote?.exportedAt ?? 0)
        case .inSync:
            return .inSync
        case .unavailable:
            return .unavailable
        case .autoOff:
            return .autoOff
        case .nothingToUpload:
            return .nothingToUpload
        case .waitingForDebounce:
            return .waitingForDebounce
        }
    }

    func snapshot(accountId: String, activeAccountId: String) -> Result<ICloudRemoteSnapshot?, ICloudSyncOutcome> {
        switch readRemote(accountId: accountId) {
        case .missing:
            return .success(nil)
        case .snapshot(let backup, let json):
            let account = backup.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let active = activeAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(ICloudRemoteSnapshot(
                json: json,
                exportedAt: backup.exportedAt,
                accountId: backup.accountId,
                originDevice: backup.originDevice,
                originPlatform: backup.originPlatform,
                accountMismatch: !account.isEmpty && !active.isEmpty && account != active,
                unbound: account.isEmpty
            ))
        case .notDownloaded:
            return .failure(.notDownloaded)
        case .schemaTooNew(let version):
            return .failure(.remoteSchemaTooNew(version))
        case .unavailable:
            return .failure(.unavailable)
        case .unreadable:
            return .failure(.metadataUnavailable)
        }
    }

    private enum RemoteRead {
        case missing
        case snapshot(BackupData, json: String)
        case notDownloaded
        case schemaTooNew(Int)
        case unavailable
        case unreadable
    }

    private func readRemote(accountId: String) -> RemoteRead {
        let data: Data?
        do {
            data = try store.read(accountId: accountId)
        } catch ICloudDriveStore.Failure.notDownloaded {
            return .notDownloaded
        } catch ICloudDriveStore.Failure.unavailable {
            return .unavailable
        } catch {
            return .unreadable
        }
        guard let data else { return .missing }
        guard let text = try? BackupRestoreParser.parseToJSON(data) else { return .unreadable }
        do {
            return .snapshot(try BackupDataCodec.decode(text), json: text)
        } catch let error as BackupDecodeError {
            if case .schemaTooNew(let version) = error { return .schemaTooNew(version) }
            return .unreadable
        } catch {
            return .unreadable
        }
    }

    private static func text(_ data: Data) -> String {
        (try? BackupRestoreParser.parseToJSON(data)) ?? ""
    }
}
