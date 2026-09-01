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

    var currentWeek: WeekRef { settings.truckingWeek.currentWeek() }

    /// Re-points settings, database and sync at the account that is now signed in.
    ///
    /// Called whenever the session changes; the container swap is what guarantees one driver never
    /// sees another's journal on a shared phone.
    func applySessionScope() {
        let scope = auth.session?.scope ?? .local
        settings.rebind(to: scope)
        persistence.switchTo(scope)
        sync.refreshPendingCount()
    }

    func bootstrap() async {
        applySessionScope()
        await auth.verifyAppleCredentialIfNeeded()
        ensureProfileExists()
        await sync.registerDevice(pushToken: pushToken)
        await sync.syncNow()
    }

    func signOut(eraseLocalData: Bool = false) {
        auth.signOut(eraseLocalData: eraseLocalData)
        persistence.signOut(eraseStore: eraseLocalData)
        settings.rebind(to: .local)
        selectedTab = .journal
    }

    /// Handles a silent `type=sync` push.
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        guard userInfo["type"] as? String == "sync" else { return }
        await sync.pullOnly()
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
