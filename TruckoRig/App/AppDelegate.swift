import UIKit
import UserNotifications

/// Push registration and silent wake-ups.
///
/// Pushes are signals, never payloads: the server sends `type=sync` with `content-available` and
/// the app pulls its own data. Nothing about the account travels in a notification.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    weak var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Asks for permission and registers with APNs. Declining is fine — sync still runs in the
    /// foreground and on background refresh.
    func requestPushAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        AppLog.sync.notice("Notification permission granted: \(granted, privacy: .public)")
        UIApplication.shared.registerForRemoteNotifications()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        appState?.registerPushToken(token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        AppLog.sync.error("APNs registration failed")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await appState?.handleRemoteNotification(userInfo: userInfo)
        return .newData
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Sync pushes are silent by contract; anything else the server sends can still be shown.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        return userInfo["type"] as? String == "sync" ? [] : [.banner, .sound]
    }
}
