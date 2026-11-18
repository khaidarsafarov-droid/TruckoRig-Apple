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
    var mediaEnabled: Bool
    var wifiOnly: Bool
    /// Directory-backed tests start on Wi-Fi. A live container waits for the path monitor.
    var onWifi: Bool
    var lowPowerModeOverride: Bool?
    var mediaStoreOverride: MediaStore?
    private(set) var mediaByteCount: Int64 = 0
    private(set) var mediaBytesKnown = false
    private(set) var mediaProgress: ICloudMediaPolicy.Progress?
    private(set) var mediaNotice: MediaNotice = .none

    enum MediaNotice: Equatable {
        case none
        case waitingForWifi
        case waitingForPower
        case downloading
        case saved
        case failed
        case unsupported
    }

    var lastMediaUploadAt: Int64 { prefs.lastMediaUploadAt }

    var displayedMediaBytes: Int64 {
        mediaBytesKnown ? mediaByteCount : prefs.lastMediaBytes
    }

    /// Reloads the journal after a confirmed restore.
    var onJournalRestored: (() -> Void)?

    @ObservationIgnored private let store: ICloudDriveStore
    @ObservationIgnored private let prefs: ICloudBackupPrefs
    @ObservationIgnored private let engine: ICloudSyncEngine
    @ObservationIgnored private let mediaEngine: ICloudMediaEngine
    @ObservationIgnored private let pathMonitor = ICloudPathMonitor()
    @ObservationIgnored private let watcher = ICloudMetadataWatcher()
    @ObservationIgnored private var didScheduleMedia = false
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
        self.mediaEngine = ICloudMediaEngine(store: store)
        self.accountId = accountId
        self.autoSyncEnabled = prefs.autoSyncEnabled
        self.mediaEnabled = prefs.mediaEnabled
        self.wifiOnly = prefs.wifiOnly
        self.onWifi = !store.monitorsUbiquity
    }

    func bind(database: AppDatabase, settings: AppSettings, scope: AccountScope) {
        self.database = database
        self.settings = settings
        self.scope = scope
    }

    func start() {
        #if SIDELOAD
        availability = .signedOut
        return
        #else
        if UITestLaunch.suppressesSystemPrompts && store.monitorsUbiquity {
            availability = .signedOut
            return
        }
        Task { await refreshAvailabilityAndSnapshot() }
        if !UITestLaunch.suppressesSystemPrompts {
            ICloudBackgroundRegistrar.submit()
        }
        if store.monitorsUbiquity && !UITestLaunch.suppressesSystemPrompts {
            pathMonitor.start { [weak self] wifi in
                Task { @MainActor in
                    self?.noteWifi(wifi)
                }
            }
        }
        if !didScheduleMedia {
            didScheduleMedia = true
            scheduleMediaBackup(after: ICloudMediaPolicy.backgroundDelayAfterChange)
        }
        #endif
    }

    func setMediaEnabled(_ enabled: Bool) {
        mediaEnabled = enabled
        prefs.mediaEnabled = enabled
        if enabled {
            scheduleMediaBackup(after: ICloudMediaPolicy.backgroundDelayAfterChange)
        }
    }

    func setWifiOnly(_ enabled: Bool) {
        wifiOnly = enabled
        prefs.wifiOnly = enabled
    }

    func setAutoSync(_ enabled: Bool) {
        autoSyncEnabled = enabled
        prefs.autoSyncEnabled = enabled
        if enabled { noteLocalChange() }
    }

    /// Debounced push after a journal edit. Background and the processing task do not wait.
    func noteLocalChange() {
        #if SIDELOAD
        return
        #else
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
        scheduleMediaBackup(after: ICloudMediaPolicy.backgroundDelayAfterChange)
        #endif
    }

    func syncOnBackground() {
        #if SIDELOAD
        return
        #else
        guard !UITestLaunch.suppressesSystemPrompts || !store.monitorsUbiquity else { return }
        debounceTask?.cancel()
        generation += 1
        Task { await self.sync(debounceElapsed: true) }
        scheduleMediaBackup(after: 30)
        #endif
    }

    func syncNow() async {
        await sync(debounceElapsed: true, manual: true)
        await uploadMedia(userRequested: true, backgroundTask: false)
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
            media: makeMediaStore(),
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

    /// Journal first, then photos and scans. A missing file is skipped.
    func restoreConfirmed() async throws -> ICloudRestoreOutcome {
        busy = true
        defer {
            busy = false
            mediaProgress = nil
        }
        let report = try restore(confirmed: true)
        let media = await restoreMediaBody()
        return ICloudRestoreOutcome(journal: report, media: media.payload, applied: media.applied)
    }

    func restoreMedia() async -> ICloudMediaApplyResult {
        let ownsBusy = !busy
        if ownsBusy { busy = true }
        defer {
            if ownsBusy {
                busy = false
                mediaProgress = nil
            }
        }
        return await restoreMediaBody()
    }

    /// Background processing task for photos and scans. A missing network retries.
    /// Wi-Fi and low power reschedule instead of uploading.
    func performMediaBackground() async -> Bool {
        let outcome = await uploadMedia(userRequested: false, backgroundTask: true)
        switch outcome {
        case .failed, .notDownloaded:
            return false
        case .skipWifi, .skipLowPower:
            ICloudMediaBackground.submit(after: ICloudMediaPolicy.backgroundRetryDelay)
            return true
        case .uploaded, .unchanged:
            ICloudMediaBackground.submit(after: ICloudBackupPolicy.periodicInterval)
            return true
        case .disabled, .unavailable, .unsupported, .deferred:
            return true
        }
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
        watcher.start(fileNames: [
            ICloudBackupPolicy.containerFileName(accountId: accountId),
            ICloudMediaPolicy.manifestFileName,
        ]) { [weak self] in
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
        refreshMediaSummary()
    }

    private func apply(_ outcome: ICloudSyncOutcome) {
        switch outcome {
        case .uploaded:
            notice = .saved
        case .failed, .metadataUnavailable:
            notice = .failed
        case .refusedSecret:
            break
        case .notDownloaded:
            notice = .downloading
        case .remoteSchemaTooNew:
            notice = .schemaTooNew
        case .keepRemote, .inSync:
            if notice == .schemaTooNew || notice == .downloading { return }
            if notice == .failed { notice = .none }
        case .unavailable, .autoOff, .nothingToUpload, .waitingForDebounce:
            break
        }
    }

    private func makeMediaStore() -> MediaStore {
        mediaStoreOverride ?? MediaStore(scope: scope)
    }

    private func scheduleMediaBackup(after delay: TimeInterval) {
        guard mediaEnabled else { return }
        ICloudMediaBackground.submit(after: delay)
    }

    private func noteWifi(_ wifi: Bool) {
        let was = onWifi
        onWifi = wifi
        if wifi && !was {
            scheduleMediaBackup(after: ICloudMediaPolicy.backgroundDelayAfterChange)
        }
    }

    private enum MediaUploadResult {
        case uploaded
        case unchanged
        case notDownloaded
        case failed
        case skipWifi
        case skipLowPower
        case disabled
        case unavailable
        case unsupported
        case deferred
    }

    @discardableResult
    private func uploadMedia(userRequested: Bool, backgroundTask: Bool) async -> MediaUploadResult {
        let ownsBusy = !busy
        if ownsBusy { busy = true }
        defer { if ownsBusy { busy = false } }
        await refreshAvailability()
        let decision = ICloudMediaPolicy.gate(ICloudMediaPolicy.Conditions(
            availability: availability,
            mediaEnabled: mediaEnabled,
            wifiOnly: wifiOnly,
            onWifi: onWifi,
            lowPowerMode: lowPowerModeOverride ?? ProcessInfo.processInfo.isLowPowerModeEnabled,
            userRequested: userRequested,
            backgroundTask: backgroundTask
        ))
        switch decision {
        case .unavailable:
            mediaNotice = .none
            return .unavailable
        case .skipDisabled:
            return .disabled
        case .skipWifi:
            mediaNotice = .waitingForWifi
            if !backgroundTask {
                ICloudMediaBackground.submit(after: ICloudMediaPolicy.backgroundRetryDelay)
            }
            return .skipWifi
        case .skipLowPower:
            mediaNotice = .waitingForPower
            if !backgroundTask {
                ICloudMediaBackground.submit(after: ICloudMediaPolicy.backgroundRetryDelay)
            }
            return .skipLowPower
        case .deferToBackground:
            mediaNotice = .waitingForPower
            ICloudMediaBackground.submit(after: ICloudMediaPolicy.backgroundDelayAfterChange)
            return .deferred
        case .uploadNow:
            break
        }
        guard let database else { return .unchanged }
        let graph: AppDatabase.StoredGraph
        do {
            graph = try database.fetchGraph()
        } catch {
            mediaNotice = .failed
            return .failed
        }
        let snapshot = ICloudMediaLibrary.snapshot(graph: graph, store: makeMediaStore())
        let report = mediaEngine.upload(
            accountId: accountId,
            items: snapshot.items,
            bytes: snapshot.bytes,
            now: Self.nowMillis()
        )
        switch report.outcome {
        case .uploaded:
            mediaNotice = .saved
            prefs.lastMediaUploadAt = Self.nowMillis()
            prefs.lastError = nil
        case .unchanged:
            if mediaNotice == .waitingForWifi || mediaNotice == .waitingForPower || mediaNotice == .failed {
                mediaNotice = .none
            }
        case .notDownloaded:
            mediaNotice = .downloading
        case .unsupported:
            mediaNotice = .unsupported
        case .failed:
            mediaNotice = .failed
            prefs.lastError = "icloud_media_failed"
        }
        refreshMediaSummary()
        switch report.outcome {
        case .uploaded: return .uploaded
        case .unchanged: return .unchanged
        case .notDownloaded: return .notDownloaded
        case .unsupported: return .unsupported
        case .failed: return .failed
        }
    }

    private func restoreMediaBody() async -> ICloudMediaApplyResult {
        guard let database else {
            return ICloudMediaApplyResult(
                payload: ICloudMediaRestorePayload(
                    files: [], bytes: [:], unavailable: [], unsupported: false, manifestNotReady: false
                ),
                applied: ICloudMediaLibrary.Applied(restored: 0, recordIds: [])
            )
        }
        let payload = await mediaEngine.restore(accountId: accountId) { [weak self] progress in
            self?.mediaProgress = progress
        }
        if payload.unsupported {
            mediaNotice = .unsupported
        } else if payload.manifestNotReady {
            mediaNotice = .downloading
        }
        let loads = (try? database.fetchGraph().loads) ?? []
        let applied = ICloudMediaLibrary.apply(payload, to: database, media: makeMediaStore(), loads: loads)
        return ICloudMediaApplyResult(payload: payload, applied: applied)
    }

    private func refreshMediaSummary() {
        switch mediaEngine.inspect(accountId: accountId) {
        case .ready(let manifest):
            mediaByteCount = ICloudMediaPolicy.totalBytes(manifest.items)
            mediaBytesKnown = true
            prefs.lastMediaBytes = mediaByteCount
            if mediaNotice == .downloading { mediaNotice = .none }
        case .missing:
            mediaByteCount = 0
            mediaBytesKnown = true
            prefs.lastMediaBytes = 0
        case .notDownloaded:
            if mediaNotice == .none || mediaNotice == .saved { mediaNotice = .downloading }
        case .unsupported:
            mediaNotice = .unsupported
        case .failed:
            break
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
             .waitingForDebounce, .remoteSchemaTooNew, .refusedSecret:
            return false
        }
    }
}

enum ICloudBackgroundRegistrar {
    static let identifier = ICloudBackupPolicy.backgroundTaskIdentifier
    private static var registered = false

    static func register() {
        #if SIDELOAD
        return
        #else
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
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ICloudMediaPolicy.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task { @MainActor in
                let ok = await ICloudBackupRuntime.performMediaSync()
                task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
            }
        }
        #endif
    }

    static func submit() {
        #if SIDELOAD
        return
        #else
        guard !UITestLaunch.suppressesSystemPrompts else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = ICloudBackupPolicy.requiresNetwork
        request.requiresExternalPower = BackupSchedule.requiresExternalPower
        request.earliestBeginDate = Date(timeIntervalSinceNow: ICloudBackupPolicy.periodicInterval)
        try? BGTaskScheduler.shared.submit(request)
        #endif
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

    @MainActor
    static func performMediaSync() async -> Bool {
        if UITestLaunch.suppressesSystemPrompts { return true }
        if let controller { return await controller.performMediaBackground() }
        let persistence = PersistenceController(scope: .local)
        let settings = AppSettings(scope: .local)
        let controller = ICloudBackupController()
        controller.bind(database: persistence.database, settings: settings, scope: .local)
        return await controller.performMediaBackground()
    }
}
