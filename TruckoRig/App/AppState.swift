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
    let sync: SyncEngine

    var selectedTab: MainTab = .journal
    /// APNs device token, forwarded to the backend once an account exists.
    var pushToken: String?

    init() {
        let restored = AuthSessionStore.load()
        let scope = restored?.scope ?? .local

        let settings = AppSettings(scope: scope)
        let persistence = PersistenceController(scope: scope)
        let auth = AuthManager(settings: settings)

        self.settings = settings
        self.persistence = persistence
        self.auth = auth
        self.sync = SyncEngine(settings: settings, auth: auth, persistence: persistence)
    }

    /// Whether the login screen should cover the app.
    var needsAuthentication: Bool { auth.session == nil }

    /// Re-points settings, database and sync at the account that is now signed in.
    ///
    /// Called whenever the session changes; the container swap is what guarantees one driver never
    /// sees another's journal on a shared phone.
    func applySessionScope() {
        let scope = auth.session?.scope ?? .local
        settings.rebind(to: scope)
        persistence.switchTo(scope)
        sync.refreshPending()
    }

    func bootstrap() async {
        applySessionScope()
        await auth.verifyAppleCredentialIfNeeded()
        ensureProfileExists()
        publishWidgetSnapshot()
        await sync.registerDevice(pushToken: pushToken)
        await sync.syncNow()
    }

    func signOut(eraseLocalData: Bool = false) {
        auth.signOut(eraseLocalData: eraseLocalData)
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

    /// Entry point for background refresh: sync, then refresh the widget.
    func syncFromBackground() async {
        await sync.syncNow()
        publishWidgetSnapshot()
    }

    /// Handles a silent `type=sync` push.
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        guard userInfo["type"] as? String == "sync" else { return }
        await sync.pullOnly()
        publishWidgetSnapshot()
    }

    /// The only way views should obtain a load repository: writes also refresh the widget.
    func loadRepository(in context: ModelContext) -> LoadRepository {
        LoadRepository(
            context: context,
            sync: sync,
            week: settings.truckingWeek,
            onDidSave: { [weak self] in self?.publishWidgetSnapshot() }
        )
    }

    /// Writes the weekly gross target to settings and the profile row so a later snapshot
    /// push carries the number the driver just typed, not a stale copy.
    func setWeeklyGoal(_ amount: Double) {
        settings.weeklyGoal = amount
        let context = persistence.mainContext
        if let profile = try? context.fetch(FetchDescriptor<DriverProfile>()).first {
            profile.weeklyGoal = amount
            profile.updatedAt = Date()
            sync.enqueue(.profile, id: profile.id, operation: .update, in: context)
            try? context.save()
        }
        publishWidgetSnapshot()
    }

    /// Settings follow the profile row after a pull or backup restore.
    func adoptSyncedGoal() {
        guard let profile = try? persistence.mainContext.fetch(FetchDescriptor<DriverProfile>()).first else {
            return
        }
        settings.weeklyGoal = profile.weeklyGoal
    }

    func registerPushToken(_ token: String) {
        pushToken = token
        Task { await sync.registerDevice(pushToken: token) }
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
