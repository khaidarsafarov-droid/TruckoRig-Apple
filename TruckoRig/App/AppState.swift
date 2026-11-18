import Foundation
import Observation
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case journal
    case goal
    case profile

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .journal: return "tab.journal"
        case .goal: return "tab.goal"
        case .profile: return "tab.profile"
        }
    }

    var systemImage: String {
        switch self {
        case .journal: return "list.bullet.rectangle"
        case .goal: return "target"
        case .profile: return "person.crop.circle"
        }
    }
}

/// Composition root: builds the object graph for the local store.
///
/// Everything hangs off one instance placed in the SwiftUI environment, which is the whole of the
/// app's dependency injection — no container framework, no hidden singletons.
@MainActor
@Observable
final class AppState {

    let settings: AppSettings
    let persistence: PersistenceController
    let catalog: RecordCatalog
    let premium: PremiumController
    let telegram: TelegramCoordinator
    let icloud: ICloudBackupController

    var selectedTab: MainTab = .journal

    /// Screen a widget deep link asked to open. Cleared when the cover dismisses.
    var pendingPresentation: WidgetPresentation?

    /// True after the driver refuses the alert that a ТО reminder asked for.
    var maintenanceAlertsDenied = false

    /// Active App Store subscription, including the free month. StoreKit is the only source.
    var premiumIsActive: Bool { premium.isActive }

    /// Opens the encrypted journal on this phone and copies a leftover SwiftData file once.
    convenience init() {
        LocalStoreMigration.adoptPreviousAccountIfNeeded()
        let settings = AppSettings(scope: .local)
        let persistence = PersistenceController(scope: .local)
        self.init(persistence: persistence, settings: settings, premium: PremiumController())
    }

    /// Preview and test graph. Does not touch the Keychain, the SwiftData file, or StoreKit.
    init(persistence: PersistenceController, settings: AppSettings? = nil, premium: PremiumController? = nil) {
        let resolved = settings ?? AppSettings(scope: persistence.scope)
        self.settings = resolved
        self.persistence = persistence
        let catalog = RecordCatalog()
        catalog.reload(from: persistence.database)
        self.catalog = catalog
        let controller = premium ?? PremiumController(inactiveStore: nil)
        controller.localeProvider = { [weak resolved] in
            PremiumCopy.locale(for: resolved?.language ?? .system)
        }
        self.premium = controller
        let telegram = TelegramCoordinator(
            database: persistence.database,
            settings: resolved,
            scope: persistence.scope
        )
        self.telegram = telegram
        let icloud = ICloudBackupController()
        icloud.bind(database: persistence.database, settings: resolved, scope: persistence.scope)
        self.icloud = icloud
        TelegramRuntime.coordinator = telegram
        ICloudBackupRuntime.controller = icloud
        telegram.isPremium = { [weak controller] in controller?.isActive ?? false }
        telegram.onJournalChanged = { [weak self] in
            self?.reloadJournal()
        }
        icloud.onJournalRestored = { [weak self] in
            self?.reloadJournal()
        }
    }

    func bootstrap() {
        installNotificationHandling()
        ensureProfileExists()
        hydrateImportedLoadFields()
        reloadJournal()
        premium.start()
        telegram.launch()
        TelegramBackgroundRegistrar.submit()
        icloud.start()
    }

    /// Reloads the in-memory journal and refreshes the home-screen widget.
    func reloadJournal() {
        catalog.reload(from: persistence.database)
        publishWidgetSnapshot()
        scheduleReminders()
        icloud.noteLocalChange()
    }

    /// Replaces pending smart reminders. Does not reload the journal.
    func scheduleReminders() {
        reminderTask?.cancel()
        reminderTask = Task { [weak self] in
            guard let self else { return }
            await MaintenanceReminderCenter.sync(self)
        }
    }

    /// Records that a maintenance alert was handed to the system. Skips another reminder pass.
    func markMaintenanceNotified(ids: [String], now: Date = Date()) {
        let millis = Int64(now.timeIntervalSince1970 * 1000)
        for id in ids {
            guard var task = catalog.maintenance.first(where: { $0.id == id }) else { continue }
            task.notifiedAt = millis
            task.updatedAt = millis
            try? persistence.database.save(task)
        }
        catalog.reload(from: persistence.database)
        publishWidgetSnapshot()
    }

    /// Drops the "already alerted" stamp when a mileage interval is no longer due.
    func clearMaintenanceNotified(ids: [String], now: Date = Date()) {
        guard !ids.isEmpty else { return }
        let millis = Int64(now.timeIntervalSince1970 * 1000)
        for id in ids {
            guard var task = catalog.maintenance.first(where: { $0.id == id }) else { continue }
            task.notifiedAt = nil
            task.updatedAt = millis
            try? persistence.database.save(task)
        }
        catalog.reload(from: persistence.database)
    }

    /// Marks the service done and, when it repeats, files the next occurrence.
    func completeMaintenance(_ task: MaintenanceTask, now: Date = Date()) {
        let next = MaintenanceReminderSchedule.nextTask(
            after: task,
            now: now,
            calendar: settings.truckingWeek.calendar
        )
        MaintenanceSnoozeStore.clear(task.id)
        let repository = financeRepository()
        try? repository.complete(task, now: now)
        if let next {
            try? repository.addTask(next)
        }
    }

    /// Delivers the same alert again tomorrow. Quiet hours still shift the fire time.
    func snoozeMaintenance(taskID: String, now: Date = Date()) {
        guard var task = catalog.maintenance.first(where: { $0.id == taskID }) else { return }
        let millis = Int64(now.timeIntervalSince1970 * 1000)
        task.notifiedAt = nil
        task.updatedAt = millis
        try? persistence.database.save(task)
        MaintenanceSnoozeStore.set(now.addingTimeInterval(MaintenanceReminderSchedule.snoozeInterval), for: taskID)
        reloadJournal()
    }

    func installNotificationHandling() {
        premium.observeMaintenanceActions { [weak self] action, taskID in
            self?.handleMaintenanceNotification(action: action, taskID: taskID)
        }
        premium.installNotificationDelegate()
    }

    func handleMaintenanceNotification(action: String, taskID: String) {
        if catalog.maintenance.contains(where: { $0.id == taskID }) == false {
            catalog.reload(from: persistence.database)
        }
        guard let task = catalog.maintenance.first(where: { $0.id == taskID }) else { return }
        if action == MaintenanceAlertPoster.doneAction {
            completeMaintenance(task)
            return
        }
        if action == MaintenanceAlertPoster.snoozeAction {
            snoozeMaintenance(taskID: taskID)
            return
        }
        markMaintenanceNotified(ids: [taskID])
    }

    @ObservationIgnored private var reminderTask: Task<Void, Never>?

    /// Refreshes the home-screen widget from the current week.
    ///
    /// The SQLCipher key stays in this process. Only the finished numbers are written to the App Group.
    func publishWidgetSnapshot(now: Date = Date()) {
        let week = settings.truckingWeek
        let ref = week.currentWeek(now: now)
        let loads = catalog.loads.filter { $0.weekNumber == ref.weekNumber && $0.year == ref.year }
        let progress = WeeklyGoalCalculator(week: week, locale: snapshotLocale).calculate(
            target: settings.weeklyGoal,
            loads: loads.map(\.summary),
            for: ref,
            now: now
        )
        guard let start = week.startDate(of: ref), let end = week.endDate(of: ref) else { return }
        let snapshot = WidgetSnapshotBuilder.make(
            progress: progress,
            weekStart: start,
            weekEnd: end,
            calendar: week.calendar,
            locale: snapshotLocale,
            now: now
        )
        WidgetBridge.publish(snapshot)
    }

    /// Widget and home-screen links. Unknown `truckorig://` paths open the journal.
    func open(_ url: URL) {
        guard let route = WidgetDeepLink.route(from: url) else { return }
        switch route {
        case .home:
            selectedTab = .journal
            pendingPresentation = nil
        case .weeklyGoal:
            selectedTab = .goal
            pendingPresentation = nil
        case .analytics:
            selectedTab = .journal
            pendingPresentation = .analytics
        case .camera:
            selectedTab = .journal
            pendingPresentation = .camera
        case .scanner:
            selectedTab = .journal
            pendingPresentation = .scanner
        case .addDiesel:
            selectedTab = .journal
            pendingPresentation = .addDiesel
        case .addLoad:
            selectedTab = .journal
            pendingPresentation = .addLoad
        }
    }

    private var snapshotLocale: Locale {
        if let identifier = settings.language.localeIdentifier {
            return Locale(identifier: identifier)
        }
        return .current
    }

    /// The only way views should obtain a load repository: writes also refresh the journal.
    func loadRepository() -> LoadRepository {
        LoadRepository(
            database: persistence.database,
            week: settings.truckingWeek,
            onDidSave: { [weak self] in self?.reloadJournal() }
        )
    }

    func financeRepository() -> FinanceRepository {
        FinanceRepository(
            database: persistence.database,
            week: settings.truckingWeek,
            onDidSave: { [weak self] in self?.reloadJournal() }
        )
    }

    func mediaRepository(store: MediaStore? = nil) -> MediaRepository {
        MediaRepository(
            database: persistence.database,
            store: store ?? MediaStore(scope: persistence.scope),
            onDidSave: { [weak self] in self?.reloadJournal() }
        )
    }

    /// Writes the weekly gross target to settings and the profile row.
    func setWeeklyGoal(_ amount: Double) {
        settings.weeklyGoal = amount
        if let profile = catalog.profile {
            profile.weeklyGoal = amount
            profile.updatedAt = Date()
            try? persistence.database.save(profile)
        }
        reloadJournal()
    }

    /// Settings follow the profile row after a backup restore.
    func adoptRestoredGoal() {
        catalog.reload(from: persistence.database)
        if let profile = catalog.profile {
            settings.weeklyGoal = profile.weeklyGoal
        }
    }

    func saveProfile(_ profile: DriverProfile) {
        profile.updatedAt = Date()
        try? persistence.database.save(profile)
        reloadJournal()
    }

    /// Exactly one profile row; created lazily on first launch.
    /// Copies equipment, deadhead and dispute flags that older restores kept only in the backup book.
    private func hydrateImportedLoadFields() {
        let book = BackupIdentityStore.standard().load()
        guard !book.loadExtras.isEmpty else { return }
        guard let loads = try? persistence.database.loads() else { return }
        for load in loads {
            guard let extra = book.loadExtras[load.id.uuidString] else { continue }
            var changed = false
            if load.equipmentType == nil, let type = extra.equipmentType {
                load.equipmentType = type
                changed = true
            }
            if load.deadheadMiles == 0, extra.deadheadMiles > 0 {
                load.deadheadMiles = extra.deadheadMiles
                changed = true
            }
            if !load.disputeApplyToLoad, extra.disputeApplyToLoad {
                load.disputeApplyToLoad = true
                changed = true
            }
            if !load.disputeAmountApplied, extra.disputeAmountApplied {
                load.disputeAmountApplied = true
                changed = true
            }
            if changed {
                try? persistence.database.save(load)
            }
        }
    }

    private func ensureProfileExists() {
        catalog.reload(from: persistence.database)
        guard catalog.profile == nil else { return }
        let profile = DriverProfile(
            name: LocalStoreMigration.inheritedDisplayName,
            preferredLanguage: settings.language,
            weeklyGoal: settings.weeklyGoal
        )
        try? persistence.database.save(profile)
    }
}
