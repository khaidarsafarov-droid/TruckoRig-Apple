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

    /// Loads just imported from the share sheet. The journal draws a gold stroke until this clears.
    var highlightedLoadIDs: Set<UUID> = []

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
        catalog.reloadNow(from: persistence.database)
        self.catalog = catalog
        let journalSaves = JournalSaveNotifier()
        self.journalSaves = journalSaves
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
        telegram.onJournalChanged = { [weak self] tables in
            self?.reloadJournal(tables)
        }
        icloud.onJournalRestored = { [weak self] in
            self?.reloadJournal()
        }
        journalSaves.deliver = { [weak self] tables in
            self?.reloadJournal(tables)
        }
    }

    @ObservationIgnored private let journalSaves: JournalSaveNotifier

    func bootstrap() {
        installNotificationHandling()
        ensureProfileExists()
        hydrateImportedLoadFields()
        reloadJournal()
        ShareImportNotifier.shared.onImport = { [weak self] in
            Task { @MainActor in
                self?.importSharedLoads()
            }
        }
        ShareImportNotifier.shared.start()
        importSharedLoads()
        premium.start()
        telegram.launch()
        TelegramBackgroundRegistrar.submit()
        icloud.start()
    }

    /// Reloads the tables a write changed. The SQL runs off the main actor. Widget, share index,
    /// and reminders run only when those tables feed them.
    func reloadJournal(_ tables: JournalTables = .all) {
        catalog.reload(tables, from: persistence.database) { [weak self] in
            self?.publishAfterReload(tables)
        }
    }

    private func publishAfterReload(_ tables: JournalTables) {
        if tables.contains(.loads) || tables.contains(.profile) {
            WidgetBridge.publishWeek(loads: catalog.loads, settings: settings)
        }
        if tables.contains(.loads) {
            ShareImportIndexPublisher.publish(loads: catalog.loads)
        }
        if !tables.isDisjoint(with: [.loads, .paychecks, .diesel, .maintenance]) {
            scheduleReminders()
        }
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

    func installNotificationHandling() {
        premium.observeMaintenanceActions { [weak self] action, taskID in
            guard let self else { return }
            MaintenanceReminderCenter.handle(action: action, taskID: taskID, in: self)
        }
        premium.installNotificationDelegate()
    }

    @ObservationIgnored private var reminderTask: Task<Void, Never>?

    /// Pulls share-sheet loads into the journal. Safe to call when the App Group is missing.
    func importSharedLoads() {
        ShareImportProcessor.receive(
            loads: catalog.loads,
            repository: loadRepository(),
            media: mediaRepository(),
            highlight: { [weak self] ids in self?.highlightedLoadIDs = ids },
            showJournal: { [weak self] in self?.selectedTab = .journal }
        )
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

    /// The only way views should obtain a load repository: writes also refresh the journal.
    func loadRepository() -> LoadRepository {
        LoadRepository(
            database: persistence.database,
            week: settings.truckingWeek,
            saves: journalSaves
        )
    }

    func financeRepository() -> FinanceRepository {
        FinanceRepository(
            database: persistence.database,
            week: settings.truckingWeek,
            saves: journalSaves
        )
    }

    func mediaRepository(store: MediaStore? = nil) -> MediaRepository {
        MediaRepository(
            database: persistence.database,
            store: store ?? MediaStore(scope: persistence.scope),
            saves: journalSaves
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
        reloadJournal(.profile)
    }

    /// Settings follow the profile row after a backup restore.
    func adoptRestoredGoal() {
        catalog.reloadNow(from: persistence.database)
        if let profile = catalog.profile {
            settings.weeklyGoal = profile.weeklyGoal
        }
    }

    func saveProfile(_ profile: DriverProfile) {
        profile.updatedAt = Date()
        try? persistence.database.save(profile)
        reloadJournal(.profile)
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
        catalog.reloadNow(.profile, from: persistence.database)
        guard catalog.profile == nil else { return }
        let profile = DriverProfile(
            name: LocalStoreMigration.inheritedDisplayName,
            preferredLanguage: settings.language,
            weeklyGoal: settings.weeklyGoal
        )
        try? persistence.database.save(profile)
    }
}
