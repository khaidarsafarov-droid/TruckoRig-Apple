import Foundation
import Observation
import SwiftData
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

/// Composition root: builds the object graph and keeps the open database in step with the account.
///
/// Everything hangs off one instance placed in the SwiftUI environment, which is the whole of the
/// app's dependency injection — no container framework, no hidden singletons.
@MainActor
@Observable
final class AppState {

    let settings: AppSettings
    let persistence: PersistenceController
    let auth: AuthManager

    var selectedTab: MainTab = .journal

    init() {
        let restored = AuthSessionStore.load()
        let scope = restored?.scope ?? .local

        let settings = AppSettings(scope: scope)
        let persistence = PersistenceController(scope: scope)
        let auth = AuthManager()

        self.settings = settings
        self.persistence = persistence
        self.auth = auth
    }

    /// Whether the login screen should cover the app.
    var needsAuthentication: Bool { auth.session == nil }

    /// Re-points settings and the database at the account that is now signed in.
    ///
    /// Called whenever the session changes; the container swap is what guarantees one driver never
    /// sees another's journal on a shared phone.
    func applySessionScope() {
        let scope = auth.session?.scope ?? .local
        settings.rebind(to: scope)
        persistence.switchTo(scope)
    }

    func bootstrap() async {
        applySessionScope()
        await auth.verifyAppleCredentialIfNeeded()
        ensureProfileExists()
        publishWidgetSnapshot()
    }

    func signOut(eraseLocalData: Bool = false) {
        auth.signOut()
        persistence.signOut(eraseStore: eraseLocalData)
        settings.rebind(to: .local)
        selectedTab = .journal
        WidgetBridge.clear()
    }

    /// Refreshes the home-screen widget from the current week.
    func publishWidgetSnapshot(now: Date = Date()) {
        let week = settings.truckingWeek
        let ref = week.currentWeek(now: now)
        let weekNumber = ref.weekNumber
        let year = ref.year
        let descriptor = FetchDescriptor<Load>(
            predicate: #Predicate { $0.weekNumber == weekNumber && $0.year == year }
        )
        guard let loads = try? persistence.mainContext.fetch(descriptor) else { return }
        let progress = WeeklyGoalCalculator(week: week).calculate(
            target: settings.weeklyGoal,
            loads: loads.map(\.summary),
            for: ref,
            now: now
        )
        WidgetBridge.publish(progress)
    }

    /// The only way views should obtain a load repository: writes also refresh the widget.
    func loadRepository(in context: ModelContext) -> LoadRepository {
        LoadRepository(
            context: context,
            week: settings.truckingWeek,
            onDidSave: { [weak self] in self?.publishWidgetSnapshot() }
        )
    }

    func financeRepository(in context: ModelContext) -> FinanceRepository {
        FinanceRepository(context: context, week: settings.truckingWeek)
    }

    func mediaRepository(in context: ModelContext, store: MediaStore? = nil) -> MediaRepository {
        MediaRepository(
            context: context,
            store: store ?? MediaStore(scope: persistence.scope)
        )
    }

    /// Writes the weekly gross target to settings and the profile row.
    func setWeeklyGoal(_ amount: Double) {
        settings.weeklyGoal = amount
        let context = persistence.mainContext
        if let profile = try? context.fetch(FetchDescriptor<DriverProfile>()).first {
            profile.weeklyGoal = amount
            profile.updatedAt = Date()
            try? context.save()
        }
        publishWidgetSnapshot()
    }

    /// Settings follow the profile row after a backup restore.
    func adoptRestoredGoal() {
        guard let profile = try? persistence.mainContext.fetch(FetchDescriptor<DriverProfile>()).first else {
            return
        }
        settings.weeklyGoal = profile.weeklyGoal
    }

    /// Exactly one profile row per account; created lazily on first launch of that account.
    private func ensureProfileExists() {
        let context = persistence.mainContext
        let existing = try? context.fetch(FetchDescriptor<DriverProfile>())
        guard existing?.isEmpty ?? true else { return }
        let profile = DriverProfile(
            name: auth.session?.displayName,
            preferredLanguage: settings.language,
            weeklyGoal: settings.weeklyGoal
        )
        context.insert(profile)
        try? context.save()
    }
}
