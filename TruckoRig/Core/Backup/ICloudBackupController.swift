import BackgroundTasks
import Foundation
import UIKit

/// Settings and background entry for the single iCloud Drive backup file.
@MainActor
@Observable
final class ICloudBackupController {
    enum Notice: Equatable {
        case none
        case saved
        case failed
        case downloading
        case schemaTooNew
    }

    enum Refusal: Error, Equatable {
        case missing
        case blocked(ICloudBackupPolicy.ApplyBlock)
    }

    private(set) var availability: ICloudBackupPolicy.Availability = .unknown
    private(set) var remote: ICloudRemoteSnapshot?
    private(set) var notice: Notice = .none
    private(set) var busy = false
    var autoSyncEnabled: Bool

    /// Reloads the journal after a confirmed restore.
    var onJournalRestored: (() -> Void)?

    @ObservationIgnored private let store: ICloudDriveStore
    @ObservationIgnored private let prefs: ICloudBackupPrefs
    @ObservationIgnored private let engine: ICloudSyncEngine
    @ObservationIgnored private let watcher = ICloudMetadataWatcher()
    @ObservationIgnored private var database: AppDatabase?
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var scope: AccountScope = .local
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let accountId: String

    var lastSyncAt: Int64 { prefs.lastSyncAt }

    init(
        store: ICloudDriveStore = ICloudDriveStore(),
        prefs: ICloudBackupPrefs = .standard(),
        accountId: String = BackupAccount.localDev
    ) {
        self.store = store
        self.prefs = prefs
        self.engine = ICloudSyncEngine(store: store, prefs: prefs)
        self.accountId = accountId
        self.autoSyncEnabled = prefs.autoSyncEnabled
    }

    func bind(database: AppDatabase, settings: AppSettings, scope: AccountScope) {
        self.database = database
        self.settings = settings
        self.scope = scope
    }

    func start() {
        if UITestLaunch.suppressesSystemPrompts && store.monitorsUbiquity {
            availability = .signedOut
            return
        }
        Task { await refreshAvailabilityAndSnapshot() }
        if !UITestLaunch.suppressesSystemPrompts {
            ICloudBackgroundRegistrar.submit()
        }
    }

    func setAutoSync(_ enabled: Bool) {
        autoSyncEnabled = enabled
        prefs.autoSyncEnabled = enabled
        if enabled { noteLocalChange() }
    }

    /// Debounced push after a journal edit. Background and the processing task do not wait.
    func noteLocalChange() {
        guard !UITestLaunch.suppressesSystemPrompts || !store.monitorsUbiquity else { return }
        generation += 1
        let token = generation
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            let nanos = UInt64(ICloudBackupPolicy.debounce * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled, self.generation == token else { return }
            await self.sync(debounceElapsed: true)
        }
    }

    func syncOnBackground() {
        guard !UITestLaunch.suppressesSystemPrompts || !store.monitorsUbiquity else { return }
        debounceTask?.cancel()
        generation += 1
        Task { await self.sync(debounceElapsed: true) }
    }

    func syncNow() async {
        await sync(debounceElapsed: true, manual: true)
    }

    /// Reads the container without uploading. Used before a confirmed restore.
    func reloadRemote() async {
        await refreshAvailability()
        guard availability == .available else {
            remote = nil
            watcher.stop()
            return
        }
        refreshSnapshot()
    }

    /// Background processing task. Retry only when the upload itself failed.
    func performPeriodic() async -> Bool {
        let outcome = await sync(debounceElapsed: true)
        let pushed = !outcome.shouldRetry
        return BackupSchedule.periodicResult(userId: accountId, pushSucceeded: pushed) == .success
    }

    func remoteIsNewer() -> Bool {
        guard let remote, let database else { return false }
        let newest = (try? BackupService.newestLoadMillis(in: database)) ?? 0
        return ICloudBackupPolicy.resolution(
            localNewestMillis: newest,
            remoteExportedAt: remote.exportedAt,
            lastUploadedExportedAt: prefs.lastUploadedExportedAt
        ) == .keepRemote
    }

    func copyIsOlderThanLocal() -> Bool {
        guard let remote, let database else { return false }
        let newest = (try? BackupService.newestLoadMillis(in: database)) ?? 0
        return BackupSyncPolicy.shouldWarnBeforeFileRestore(
            localNewestMillis: newest,
            backupExportedAt: remote.exportedAt
        )
    }

    /// Replaces the journal only after the restore screen has been confirmed.
    @discardableResult
    func restore(confirmed: Bool) throws -> BackupService.Report {
        guard let remote, let database, let settings else { throw Refusal.missing }
        let newest = try BackupService.newestLoadMillis(in: database)
        if let block = ICloudBackupPolicy.applyBlock(
            confirmed: confirmed,
            localNewestMillis: newest,
            remoteExportedAt: remote.exportedAt,
            fileAccountId: remote.accountId,
            activeAccountId: accountId
        ) {
            throw Refusal.blocked(block)
        }
        let report = try BackupService.restoreBackupJSON(
            remote.json,
            into: database,
            settings: settings,
            identity: BackupIdentityStore.standard(accountId: accountId),
            media: MediaStore(scope: scope),
            activeAccountId: accountId,
            allowUnboundAccount: true,
            allowForeignAccount: true
        )
        prefs.lastUploadedExportedAt = remote.exportedAt
        prefs.lastSyncAt = Self.nowMillis()
        prefs.lastError = nil
        notice = .none
        onJournalRestored?()
        return report
    }

    @discardableResult
    private func sync(debounceElapsed: Bool, manual: Bool = false) async -> ICloudSyncOutcome {
        busy = true
        defer { busy = false }
        await refreshAvailability()
        guard availability == .available else {
            remote = nil
            if availability == .signedOut || availability == .containerMissing {
                notice = .none
            }
            return .unavailable
        }
        let outcome = engine.perform(makeRequest(debounceElapsed: debounceElapsed, manual: manual))
        apply(outcome)
        refreshSnapshot()
        return outcome
    }

    private func refreshAvailabilityAndSnapshot() async {
        await refreshAvailability()
        guard availability == .available else {
            remote = nil
            watcher.stop()
            return
        }
        startWatcherIfNeeded()
        refreshSnapshot()
    }

    private func refreshAvailability() async {
        if store.monitorsUbiquity {
            availability = await Task.detached(priority: .utility) {
                ICloudDriveProbe.systemAvailability()
            }.value
        } else {
            availability = store.availability()
        }
    }

    private func startWatcherIfNeeded() {
        guard store.monitorsUbiquity, availability == .available else { return }
        let name = ICloudBackupPolicy.containerFileName(accountId: accountId)
        watcher.start(fileName: name) { [weak self] in
            Task { @MainActor in
                self?.refreshSnapshot()
            }
        }
    }

    private func refreshSnapshot() {
        switch engine.snapshot(accountId: accountId, activeAccountId: accountId) {
        case .success(let snapshot):
            remote = snapshot
            if notice == .downloading { notice = .none }
        case .failure(.notDownloaded):
            remote = nil
            notice = .downloading
        case .failure(.remoteSchemaTooNew):
            remote = nil
            notice = .schemaTooNew
        case .failure(.metadataUnavailable), .failure(.failed):
            notice = .failed
        case .failure:
            remote = nil
        }
    }

    private func apply(_ outcome: ICloudSyncOutcome) {
        switch outcome {
        case .uploaded:
            notice = .saved
        case .failed, .metadataUnavailable:
            notice = .failed
        case .notDownloaded:
            notice = .downloading
        case .remoteSchemaTooNew:
            notice = .schemaTooNew
        case .keepRemote, .inSync, .unavailable, .autoOff, .nothingToUpload, .waitingForDebounce:
            if notice == .schemaTooNew || notice == .downloading { return }
            if outcome != .keepRemote && outcome != .inSync {
                return
            }
            if notice == .failed { notice = .none }
        }
    }

    private func makeRequest(debounceElapsed: Bool, manual: Bool) -> ICloudSyncRequest {
        let newest = database.flatMap { try? BackupService.newestLoadMillis(in: $0) } ?? 0
        var payload: Data?
        var hasContent = false
        if let database, let settings,
           let file = try? BackupService.exportFile(
               from: database,
               settings: settings,
               identity: BackupIdentityStore.standard(accountId: accountId),
               accountId: accountId,
               originDevice: UIDevice.current.model,
               originPlatform: ICloudBackupPolicy.originPlatformIOS
           ) {
            payload = file.data
            hasContent = true
        }
        return ICloudSyncRequest(
            accountId: accountId,
            localNewestMillis: newest,
            hasExportableContent: hasContent,
            payload: payload,
            debounceElapsed: debounceElapsed,
            autoSyncEnabled: autoSyncEnabled,
            respectsAutoSwitch: !manual,
            now: Self.nowMillis()
        )
    }

    private static func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}

extension ICloudSyncOutcome {
    /// A failed push asks the processing task to retry. A missing iCloud account does not.
    var shouldRetry: Bool {
        switch self {
        case .failed, .metadataUnavailable, .notDownloaded:
            return true
        case .uploaded, .keepRemote, .inSync, .unavailable, .autoOff, .nothingToUpload,
             .waitingForDebounce, .remoteSchemaTooNew:
            return false
        }
    }
}

enum ICloudBackgroundRegistrar {
    static let identifier = ICloudBackupPolicy.backgroundTaskIdentifier
    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task { @MainActor in
                let ok = await ICloudBackupRuntime.performBackgroundSync()
                task.setTaskCompleted(success: ok)
                submit()
            }
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    static func submit() {
        guard !UITestLaunch.suppressesSystemPrompts else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = ICloudBackupPolicy.requiresNetwork
        request.requiresExternalPower = BackupSchedule.requiresExternalPower
        request.earliestBeginDate = Date(timeIntervalSinceNow: ICloudBackupPolicy.periodicInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum ICloudBackupRuntime {
    @MainActor static weak var controller: ICloudBackupController?

    @MainActor
    static func performBackgroundSync() async -> Bool {
        if UITestLaunch.suppressesSystemPrompts { return true }
        if let controller { return await controller.performPeriodic() }
        let persistence = PersistenceController(scope: .local)
        let settings = AppSettings(scope: .local)
        let controller = ICloudBackupController()
        controller.bind(database: persistence.database, settings: settings, scope: .local)
        return await controller.performPeriodic()
    }
}
