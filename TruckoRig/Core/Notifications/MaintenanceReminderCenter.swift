import Foundation
import UserNotifications

/// Hands Android's 24-hour reminder plan to `UNUserNotificationCenter`.
///
/// There is no WorkManager on iOS. The first evaluation anchors `lastRun` and schedules a
/// notification for 24 hours later. A fire time inside quiet hours moves to the exclusive end
/// of that window, including a window that crosses midnight. `start == end` quiets every hour
/// and is not scheduled. `notifiedAt` and the missing-week key are recorded when the request is
/// accepted by the system, so a closed app still delivers it once.
@MainActor
enum MaintenanceReminderCenter {

    static func sync(_ appState: AppState, now: Date = Date()) async {
        let decision = decide(appState, now: now)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: decision.cancelIdentifiers)
        guard !decision.notifications.isEmpty else {
            if let last = decision.lastRunAt {
                appState.settings.smartNotificationLastRun = last
            }
            return
        }
        guard await authorized(center) else { return }

        let calendar = appState.settings.truckingWeek.calendar
        for note in decision.notifications {
            let content = UNMutableNotificationContent()
            content.title = note.title
            content.body = note.body
            content.sound = .default
            content.threadIdentifier = note.channel
            let request = UNNotificationRequest(
                identifier: note.identifier,
                content: content,
                trigger: trigger(for: note.fireAt, now: now, calendar: calendar)
            )
            do {
                try await center.add(request)
            } catch {
                AppLog.persistence.error("Could not schedule a reminder")
                return
            }
        }
        if let last = decision.lastRunAt {
            appState.settings.smartNotificationLastRun = last
        }
        if decision.recordMissingWeek {
            let previous = appState.settings.truckingWeek.previousWeek(now: now)
            appState.settings.missingNotifiedWeek = "\(previous.year)-W\(previous.weekNumber)"
        }
        if !decision.markNotifiedIDs.isEmpty {
            appState.markMaintenanceNotified(ids: decision.markNotifiedIDs, now: now)
        }
        await MaintenanceAlertPoster.post(appState, now: now)
    }

    static func decide(_ appState: AppState, now: Date = Date()) -> SmartNotificationDecision {
        let settings = appState.settings
        let week = settings.truckingWeek
        let previous = week.previousWeek(now: now)
        let weekKey = "\(previous.year)-W\(previous.weekNumber)"
        return SmartNotificationEngine.evaluate(SmartNotificationRequest(
            now: now,
            calendar: week.calendar,
            lastRunAt: settings.smartNotificationLastRun,
            quietEnabled: settings.quietHoursEnabled,
            quietStartHour: settings.quietStartHour,
            quietEndHour: settings.quietEndHour,
            allowMissingWeek: settings.notifyMissingWeek,
            allowMaintenance: settings.notifyMaintenance,
            hasPaycheckForLastWeek: appState.catalog.paychecks.contains {
                $0.weekNumber == previous.weekNumber && $0.year == previous.year
            },
            dieselEntriesLastWeek: dieselCount(in: previous, week: week, fills: appState.catalog.diesel),
            alreadyNotifiedMissingWeek: settings.missingNotifiedWeek == weekKey,
            missingWeekNumber: previous.weekNumber,
            maintenanceDue: [],
            russian: prefersRussian(settings.language),
            french: prefersFrench(settings.language)
        ))
    }

    /// iOS diesel rows have no week number, so the purchase date is tested against the same
    /// reporting week as paychecks.
    static func dieselCount(in weekRef: WeekRef, week: TruckingWeek, fills: [Diesel]) -> Int {
        guard let start = week.startDate(of: weekRef), let end = week.endDate(of: weekRef) else { return 0 }
        let endExclusive = week.calendar.date(byAdding: .day, value: 1, to: end) ?? end
        return fills.filter { $0.date >= start && $0.date < endExclusive }.count
    }

    static func prefersRussian(_ language: AppLanguage) -> Bool {
        switch language {
        case .russian: return true
        case .english, .french, .spanish: return false
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("ru") == true
        }
    }

    static func prefersFrench(_ language: AppLanguage) -> Bool {
        switch language {
        case .french: return true
        case .russian, .english, .spanish: return false
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("fr") == true
        }
    }

    private static func authorized(_ center: UNUserNotificationCenter) async -> Bool {
        // Unit-test and UI-test launches must not be covered by the notification prompt.
        if UITestLaunch.suppressesSystemPrompts { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    private static func trigger(for fireAt: Date, now: Date, calendar: Calendar) -> UNNotificationTrigger? {
        if fireAt.timeIntervalSince(now) <= 1 { return nil }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }
}
