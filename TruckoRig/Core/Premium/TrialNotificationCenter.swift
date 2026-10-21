import Foundation
import UserNotifications

enum TrialNotificationPermission: Equatable {
    case authorized
    case denied
    case notDetermined
}

/// One local notification per purchase, built with `UNCalendarNotificationTrigger`.
@MainActor
protocol TrialNotificationCenter: AnyObject {
    func authorization() async -> TrialNotificationPermission
    func requestAuthorization() async -> Bool
    func add(
        id: String,
        title: String,
        body: String,
        actionTitle: String,
        components: DateComponents
    ) async throws
    func remove(identifiers: [String])
}

enum TrialNotificationTrigger {
    /// Fires once, on the calendar components StoreKit's trial end minus the three-day lead.
    static func calendar(matching components: DateComponents) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}

enum PremiumReminder {
    static let categoryID = "truckorig.trial"

    static func notificationID(purchaseID: String) -> String {
        "truckorig.trial.\(purchaseID)"
    }
}

@MainActor
final class SystemTrialNotificationCenter: TrialNotificationCenter {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorization() async -> TrialNotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted
    }

    func add(
        id: String,
        title: String,
        body: String,
        actionTitle: String,
        components: DateComponents
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = PremiumReminder.categoryID
        let action = UNNotificationAction(
            identifier: "manage",
            title: actionTitle,
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: PremiumReminder.categoryID,
            actions: [action],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        let trigger = TrialNotificationTrigger.calendar(matching: components)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
    }

    func remove(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Opens subscription management when the driver taps the reminder.
final class TrialNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: () -> Void = {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        guard id.hasPrefix("truckorig.trial.") else { return }
        onOpen()
    }
}
