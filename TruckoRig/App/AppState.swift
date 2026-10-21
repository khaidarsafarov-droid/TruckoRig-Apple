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

    var selectedTab: MainTab = .journal

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
    }

    func bootstrap() {
        ensureProfileExists()
        reloadJournal()
        premium.start()
    }

    /// Reloads the in-memory journal and refreshes the home-screen widget.
    func reloadJournal() {
        catalog.reload(from: persistence.database)
        publishWidgetSnapshot()
    }

    /// Refreshes the home-screen widget from the current week.
    func publishWidgetSnapshot(now: Date = Date()) {
        let week = settings.truckingWeek
        let ref = week.currentWeek(now: now)
        let loads = catalog.loads.filter { $0.weekNumber == ref.weekNumber && $0.year == ref.year }
        let progress = WeeklyGoalCalculator(week: week).calculate(
            target: settings.weeklyGoal,
            loads: loads.map(\.summary),
            for: ref,
            now: now
        )
        WidgetBridge.publish(progress)
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
