import BackgroundTasks
import SwiftUI

@main
struct TruckoRigApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .modelContainer(appState.persistence.container)
                .tint(.forestPrimary)
                .environment(\.locale, resolvedLocale)
                .task {
                    appDelegate.appState = appState
                    await appState.bootstrap()
                }
        }
        .backgroundTask(.appRefresh(BackgroundSync.taskIdentifier)) {
            await BackgroundSync.schedule()
            await appState.sync.syncNow()
        }
    }

    /// Honours the in-app language picker; `.system` falls through to the device setting.
    private var resolvedLocale: Locale {
        guard let identifier = appState.settings.language.localeIdentifier else { return .current }
        return Locale(identifier: identifier)
    }
}

/// Background refresh registration.
///
/// The server only ever sends a wake-up push, so the app also schedules its own periodic refresh
/// for drivers who deny notification permission.
enum BackgroundSync {
    static let taskIdentifier = "com.truckorig.sync.refresh"
    /// iOS treats this as a floor, not a promise.
    static let interval: TimeInterval = 15 * 60

    static func schedule() async {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            AppLog.sync.notice("Background refresh could not be scheduled")
        }
    }
}
