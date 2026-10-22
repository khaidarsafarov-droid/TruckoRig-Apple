import Foundation
import Network

enum DriveRestoreUI: Equatable {
    case restored(loads: Int, paychecks: Int, diesel: Int)
    case unbound
    case failed
}

/// Settings and background entry point for Google Drive backup.
///
/// The journal account is always `local_dev`. The Google account is only the Drive destination.
@MainActor
@Observable
final class DriveCoordinator {
    let prefs: DriveBackupPrefs
    private let identity: DriveIdentityStore
    private let database: AppDatabase
    private let settings: AppSettings
    private let media: MediaStore
    private let transport: DriveTransport
    private var session: GoogleDriveAccount?
    private var debounce: Task<Void, Never>?
    private let monitor = NWPathMonitor()

    var suppressSchedule = false
    var busy = false
    var offline = false
    var notice: String?
    var email: String?
    var autoSyncEnabled = true
    var lastSyncAt: Int64 = 0
    var lastError: String?
    var onJournalChanged: (() -> Void)?

    let clientID: String?

    init(
        database: AppDatabase,
        settings: AppSettings,
        media: MediaStore,
        prefs: DriveBackupPrefs? = nil,
        identity: DriveIdentityStore? = nil,
        transport: DriveTransport? = nil,
        clientID: String? = DriveCoordinator.plistClientID()
    ) {
        self.database = database
        self.settings = settings
        self.media = media
        self.prefs = prefs ?? DriveBackupPrefs.standard()
        self.identity = identity ?? DriveIdentityStore.standard()
        self.transport = transport ?? DriveURLSessionTransport()
        self.clientID = DriveSchedule.validatedClientID(clientID)
        reloadFromPrefs()
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in
                self?.offline = offline
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.truckorig.drive.net"))
    }

    var isConfigured: Bool { clientID != nil }

    func launch() {
        DriveBackgroundRegistrar.submit(replace: false)
        Task { await runAutoPush() }
    }

    /// 45 seconds after a load, paycheck, diesel or maintenance edit, same delay as Android.
    func noteLocalEdit() {
        guard !suppressSchedule else { return }
        debounce?.cancel()
        debounce = Task { [weak self] in
            let nanos = UInt64(DriveSchedule.autoBackupDebounceSeconds) * 1_000_000_000
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await self?.runAutoPush()
        }
    }

    /// BGProcessingTask entry. A skipped push is success. A failed upload asks the system to retry.
    func runPeriodic() async -> Bool {
        let ok = await runAutoPush()
        return DriveSchedule.periodicResult(userId: prefs.accountId, pushSucceeded: ok) == .success
    }

    func setAutoSync(_ enabled: Bool) {
        prefs.autoSyncEnabled = enabled
        autoSyncEnabled = enabled
    }

    func connect() async {
        guard isConfigured, let session = account() else {
            notice = String(localized: "settings.drive.unavailable")
            return
        }
        guard DrivePresenter.topViewController() != nil else {
            notice = String(localized: "settings.drive.needWindow")
            return
        }
        busy = true
        defer { busy = false }
        switch await DriveConnectFlow.connect(session) {
        case .granted, .retryBackup:
            prefs.accountEmail = session.email ?? prefs.accountEmail
            reloadFromPrefs()
            notice = String(localized: "settings.drive.connected")
            await backupNow()
        case .cancelled:
            notice = String(localized: "settings.drive.cancelled")
        case .failed, .requestDriveConsent:
            notice = String(localized: "settings.drive.connectFailed")
        }
    }

    func backupNow() async {
        guard isConfigured else {
            notice = String(localized: "settings.drive.unavailable")
            return
        }
        guard prefs.isLinked || account()?.hasDriveScope == true else {
            notice = String(localized: "settings.drive.notLinked")
            return
        }
        busy = true
        defer { busy = false }
        switch await upload(manual: true) {
        case .saved:
            notice = String(localized: "settings.drive.saved \(prefs.accountEmail ?? "")")
        case .empty:
            notice = String(localized: "settings.drive.nothing")
        case .failed(let message):
            notice = message
        case .skipped:
            break
        }
    }

    func prepareRestoreWarning() async -> Bool {
        busy = true
        defer { busy = false }
        _ = await refreshRemote(recover: false)
        let loads = (try? database.fetchGraph().loads) ?? []
        let dirty = DriveSyncPolicy.hasLocalChangesAfterLastSync(
            updatedAt: loads.map { Self.millis($0.updatedAt) },
            parsedAt: loads.map { Self.millis($0.parsedAt) },
            lastSyncAt: prefs.lastSyncAt
        )
        return DriveSyncPolicy.shouldWarnBeforeRestore(
            localChangedAfterLastSync: dirty,
            remoteModifiedAt: prefs.remoteModifiedAt,
            lastSyncAt: prefs.lastSyncAt
        )
    }

    func restore(allowUnbound: Bool) async -> DriveRestoreUI {
        guard isConfigured else {
            notice = String(localized: "settings.drive.unavailable")
            return .failed
        }
        guard prefs.isLinked || account()?.hasDriveScope == true else {
            notice = String(localized: "settings.drive.notLinked")
            return .failed
        }
        busy = true
        defer { busy = false }
        guard let token = await accessToken() else {
            notice = String(localized: "settings.drive.notLinked")
            return .failed
        }
        let api = makeAPI(token: token)
        let downloaded = await Self.offMain { api.download() }
        let payload: (json: String, file: DriveRemoteFile)
        switch downloaded {
        case .success(let value):
            payload = value
        case .failure(let error):
            notice = Self.message(for: error)
            prefs.recordFailure(error.message, now: Self.now())
            reloadFromPrefs()
            return .failed
        }
        if DriveBackupCodec.exceedsRestoreLimit(byteCount: payload.json.utf8.count) {
            notice = String(localized: "settings.drive.tooLarge")
            return .failed
        }
        let backup: DriveBackup
        do {
            backup = try DriveBackupCodec.decode(payload.json)
        } catch let error as DriveBackupDecodeError {
            notice = Self.message(for: error)
            return .failed
        } catch {
            notice = String(localized: "settings.drive.corrupted")
            return .failed
        }
        let account = backup.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if account.isEmpty && !allowUnbound {
            return .unbound
        }
        if !account.isEmpty && account != prefs.accountId {
            notice = String(localized: "settings.drive.wrongAccount")
            return .failed
        }
        let previousWeek = settings.weekStart
        let plan = DriveJournalMapper.importBackup(backup, settings: settings, identity: identity)
        do {
            let removed = try database.applyDriveJournal(plan)
            for photo in removed.photos {
                media.delete(fileName: photo.fileName, filePath: photo.filePath, kind: .photo)
            }
            for scan in removed.scans {
                media.delete(fileName: scan.fileName, filePath: scan.filePath, kind: .scan)
            }
            if settings.weekStart != previousWeek {
                try WeekReindexer.reindex(in: database, week: settings.truckingWeek)
            }
            if let profile = try database.fetchGraph().profile {
                profile.weeklyGoal = settings.weeklyGoal
                try database.save(profile)
            }
        } catch {
            notice = String(localized: "settings.drive.corrupted")
            return .failed
        }
        let now = Self.now()
        prefs.recordSuccess(fileID: payload.file.id, remoteModifiedAt: payload.file.modifiedAt, now: now)
        reloadFromPrefs()
        suppressSchedule = true
        onJournalChanged?()
        suppressSchedule = false
        notice = String(
            localized: "settings.drive.success \(backup.loads.count) \(backup.paychecks.count) \(backup.diesel.count)"
        )
        return .restored(loads: backup.loads.count, paychecks: backup.paychecks.count, diesel: backup.diesel.count)
    }

    func disconnect() {
        account()?.signOut()
        session = nil
        prefs.accountEmail = nil
        prefs.driveFileID = nil
        prefs.lastSyncAt = 0
        prefs.remoteModifiedAt = 0
        prefs.lastSyncError = nil
        prefs.lastSyncErrorAt = 0
        prefs.autoSyncEnabled = true
        prefs.clear()
        reloadFromPrefs()
    }

    // MARK: - Upload

    @discardableResult
    func runAutoPush() async -> Bool {
        guard isConfigured else { return true }
        if offline { return false }
        await account()?.restore()
        if let email = account()?.email, account()?.hasDriveScope == true {
            prefs.accountEmail = email
            reloadFromPrefs()
        }
        let remote = await refreshRemote(recover: false)
        let probeFailed: Bool
        let remoteExists: Bool
        switch remote {
        case .failure:
            probeFailed = true
            remoteExists = false
        case .success(let exists):
            probeFailed = false
            remoteExists = exists
        }
        let graph = try? database.fetchGraph()
        let hasContent = graph.map { candidate in
            !candidate.loads.isEmpty || !candidate.paychecks.isEmpty || !candidate.diesel.isEmpty
                || !candidate.maintenance.isEmpty || !candidate.maintenanceArchive.isEmpty
        } ?? false
        let decision = DriveSchedule.autoPush(
            clientConfigured: isConfigured,
            autoSyncEnabled: prefs.autoSyncEnabled,
            isLinked: prefs.isLinked,
            scopeGranted: account()?.hasDriveScope == true,
            remoteProbeFailed: probeFailed,
            remoteExists: remoteExists,
            remoteModifiedAt: prefs.remoteModifiedAt,
            lastSyncAt: prefs.lastSyncAt,
            hasExportableContent: hasContent
        )
        switch decision {
        case .skip:
            return true
        case .metadataUnavailable:
            prefs.recordFailure("drive_metadata_unavailable", now: Self.now())
            reloadFromPrefs()
            return false
        case .upload:
            switch await upload(manual: false) {
            case .saved, .empty, .skipped:
                return true
            case .failed:
                return false
            }
        }
    }

    private enum UploadOutcome {
        case saved
        case empty
        case skipped
        case failed(String)
    }

    private func upload(manual: Bool) async -> UploadOutcome {
        guard let graph = try? database.fetchGraph() else {
            let word = "failed"
            return .failed(String(localized: "settings.drive.apiError \(word)"))
        }
        let now = Self.now()
        let backup = DriveJournalMapper.export(
            graph: graph,
            settings: settings,
            identity: identity,
            accountId: prefs.accountId,
            exportedAt: now
        )
        guard DriveBackupCodec.hasExportableContent(backup) else { return .empty }
        guard let token = await accessToken() else {
            let message = String(localized: "settings.drive.notLinked")
            if manual { return .failed(message) }
            prefs.recordFailure(message, now: now)
            reloadFromPrefs()
            return .failed(message)
        }
        let json = DriveBackupCodec.encode(backup)
        var api = makeAPI(token: token)
        var result = await Self.offMain { api.upload(json: json) }
        if case .failure(let error) = result, Self.isAuthFailure(error), let refreshed = await accessToken() {
            api = makeAPI(token: refreshed)
            result = await Self.offMain { api.upload(json: json) }
        }
        switch result {
        case .success(let file):
            prefs.recordSuccess(fileID: file.id, remoteModifiedAt: file.modifiedAt, now: Self.now())
            reloadFromPrefs()
            return .saved
        case .failure(let error):
            let message = Self.message(for: error)
            prefs.recordFailure(error.message, now: Self.now())
            reloadFromPrefs()
            return .failed(message)
        }
    }

    private func refreshRemote(recover: Bool) async -> Result<Bool, DriveFailure> {
        guard let token = await accessToken() else { return .failure(.notSignedIn) }
        let api = makeAPI(token: token)
        let result = await Self.offMain { api.refreshRemote() }
        switch result {
        case .success(let file):
            if let file {
                prefs.driveFileID = file.id
                if file.modifiedAt > 0 { prefs.remoteModifiedAt = file.modifiedAt }
            }
            reloadFromPrefs()
            return .success(file != nil)
        case .failure(let error):
            if recover, Self.isAuthFailure(error), let refreshed = await accessToken() {
                let retry = makeAPI(token: refreshed)
                let second = await Self.offMain { retry.refreshRemote() }
                if case .success(let file) = second {
                    if let file {
                        prefs.driveFileID = file.id
                        if file.modifiedAt > 0 { prefs.remoteModifiedAt = file.modifiedAt }
                    }
                    reloadFromPrefs()
                    return .success(file != nil)
                }
            }
            return .failure(error)
        }
    }

    private func account() -> GoogleDriveAccount? {
        guard let clientID else { return nil }
        if let session { return session }
        let created = GoogleDriveAccount(clientID: clientID)
        session = created
        return created
    }

    private func accessToken() async -> String? {
        guard let session = account() else { return nil }
        let token = await session.accessToken()
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeAPI(token: String) -> DriveAPI {
        DriveAPI(
            accessToken: token,
            fileName: prefs.backupFileName,
            storedFileID: prefs.driveFileID,
            transport: transport,
            sleep: { milliseconds in
                Thread.sleep(forTimeInterval: Double(milliseconds) / 1000)
            }
        )
    }

    private func reloadFromPrefs() {
        email = prefs.accountEmail
        autoSyncEnabled = prefs.autoSyncEnabled
        lastSyncAt = prefs.lastSyncAt
        lastError = prefs.lastSyncError
    }

    private static func offMain<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: body())
            }
        }
    }

    private static func isAuthFailure(_ error: DriveFailure) -> Bool {
        switch error {
        case .needsConsent, .notSignedIn:
            return true
        case .api(let message):
            return message.contains("401") || message.lowercased().contains("consent")
        default:
            return false
        }
    }

    private static func message(for error: DriveFailure) -> String {
        switch error {
        case .notSignedIn:
            return String(localized: "settings.drive.notLinked")
        case .needsConsent:
            return String(localized: "settings.drive.connectFailed")
        case .invalidJSON:
            return String(localized: "settings.drive.corrupted")
        case .api(let text), .io(let text):
            return String(localized: "settings.drive.apiError \(text)")
        }
    }

    private static func message(for error: DriveBackupDecodeError) -> String {
        switch error {
        case .invalidFormat:
            return String(localized: "settings.drive.badFormat")
        case .corrupted:
            return String(localized: "settings.drive.corrupted")
        case .schemaTooNew:
            return String(localized: "settings.drive.schema")
        }
    }

    /// Info.plist only. Nonisolated so the initializer default can read it off the main actor.
    nonisolated static func plistClientID() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }

    private static func now() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
