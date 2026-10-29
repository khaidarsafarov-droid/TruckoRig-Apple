import Foundation
import UserNotifications

/// Local notification at the first pickup. Android uses an alarm clock; iOS uses UserNotifications.
enum PickupAlarmCenter {
    static func identifier(for loadID: UUID) -> String {
        "pickup-\(loadID.uuidString)"
    }

    static func schedule(for load: Load) {
        let center = UNUserNotificationCenter.current()
        let identifier = identifier(for: load.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let when = load.firstPickupAt, when.timeIntervalSinceNow > 60 else { return }
        if UITestLaunch.suppressesSystemPrompts { return }
        Task {
            guard await authorized(center) else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "load.alarm.pickup.title")
            content.body = String(localized: "load.alarm.pickup.body \(load.tripId)")
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: when
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    static func cancel(loadID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: loadID)]
        )
    }

    private static func authorized(_ center: UNUserNotificationCenter) async -> Bool {
        if UITestLaunch.suppressesSystemPrompts { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }
}
