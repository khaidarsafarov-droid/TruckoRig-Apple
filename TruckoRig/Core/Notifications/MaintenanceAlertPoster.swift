import Foundation
import UserNotifications

/// Queues one local alert per ТО reminder and keeps the pending set in step with the journal.
@MainActor
enum MaintenanceAlertPoster {
    static let categoryID = "truckorig.maintenance"
    static let doneAction = "maint.done"
    static let snoozeAction = "maint.snooze"
    static let soundName = "MaintenanceAlert.caf"
    private static let pendingKey = "truckorig.maintenance.pendingIDs"

    static func post(_ appState: AppState, now: Date = Date()) async {
        let settings = appState.settings
        let week = settings.truckingWeek
        let loads = mileageLoads(appState, week: week)
        let tasks = appState.catalog.maintenance
        var progressByID: [String: MaintenanceProgress] = [:]
        for task in tasks {
            progressByID[task.id] = MaintenanceMileage.progress(task: task, loads: loads, today: now, week: week)
        }
        let fires = MaintenanceReminderSchedule.plan(
            tasks: tasks,
            progressByID: progressByID,
            now: now,
            calendar: week.calendar,
            quietEnabled: settings.quietHoursEnabled,
            quietStartHour: settings.quietStartHour,
            quietEndHour: settings.quietEndHour,
            snoozeUntil: MaintenanceSnoozeStore.all(),
            notificationsEnabled: settings.notifyMaintenance
        )
        let center = UNUserNotificationCenter.current()
        let previous = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        let nextIDs = fires.map(\.identifier)
        center.removePendingNotificationRequests(
            withIdentifiers: previous + nextIDs + [SmartNotificationCopy.maintenanceIdentifier] + SmartNotificationCopy.legacyMaintenanceIdentifiers
        )
        let incomplete = tasks.contains { !$0.isCompleted }
        guard incomplete, settings.notifyMaintenance else {
            UserDefaults.standard.set([], forKey: pendingKey)
            appState.maintenanceAlertsDenied = false
            try? await center.setBadgeCount(0)
            return
        }
        guard await authorized(center, appState: appState) else {
            try? await center.setBadgeCount(0)
            return
        }
        await registerCategory(center)
        let delivered = Set((await center.deliveredNotifications()).map(\.request.identifier))
        var queued: [String] = []
        var mark: [String] = []
        for fire in fires {
            if delivered.contains(fire.identifier) {
                mark.append(fire.taskID)
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "notify.maintenance.title")
            content.body = String(localized: "notify.maintenance.body \(fire.title)")
            content.sound = UNNotificationSound(named: UNNotificationSoundName(soundName))
            content.badge = NSNumber(value: fires.count)
            content.categoryIdentifier = categoryID
            content.threadIdentifier = SmartNotificationCopy.alertsChannel
            content.userInfo = ["taskID": fire.taskID]
            content.interruptionLevel = interruptionLevel
            let trigger = trigger(for: fire.fireAt, now: now, calendar: week.calendar)
            let request = UNNotificationRequest(identifier: fire.identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                queued.append(fire.identifier)
                if fire.markNotifiedWhenQueued { mark.append(fire.taskID) }
            } catch {
                AppLog.persistence.error("Could not schedule a maintenance reminder")
            }
        }
        UserDefaults.standard.set(queued, forKey: pendingKey)
        if !mark.isEmpty {
            appState.markMaintenanceNotified(ids: mark, now: now)
        }
        clearStaleMileageFlags(tasks: tasks, progressByID: progressByID, appState: appState, now: now)
        try? await center.setBadgeCount(queued.isEmpty ? 0 : fires.count)
    }

    static var interruptionLevel: UNNotificationInterruptionLevel {
        // Time Sensitive needs a paid capability. The unsigned sideload build has no entitlement,
        // so that variant stays active and still plays the bundled alert.
        #if SIDELOAD
        return .active
        #else
        return .timeSensitive
        #endif
    }

    private static func mileageLoads(_ appState: AppState, week: TruckingWeek) -> [MaintenanceMileage.LoadInput] {
        appState.catalog.loads.map { load in
            MaintenanceMileage.LoadInput(
                tripId: load.tripId,
                id: load.id.uuidString,
                miles: load.totalMiles,
                date: MaintenanceMileage.isoDay(load.date, calendar: week.calendar),
                actualFinishDate: load.actualFinishDate.map {
                    MaintenanceMileage.isoDay($0, calendar: week.calendar)
                },
                lastDeliveryAt: load.lastDeliveryAt
            )
        }
    }

    private static func authorized(_ center: UNUserNotificationCenter, appState: AppState) async -> Bool {
        if UITestLaunch.suppressesSystemPrompts {
            appState.maintenanceAlertsDenied = false
            return false
        }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            appState.maintenanceAlertsDenied = false
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            appState.maintenanceAlertsDenied = !granted
            return granted
        default:
            appState.maintenanceAlertsDenied = true
            return false
        }
    }

    private static func registerCategory(_ center: UNUserNotificationCenter) async {
        let done = UNNotificationAction(identifier: doneAction, title: String(localized: "maintenance.action.done"), options: [.foreground])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: String(localized: "maintenance.action.snooze"), options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [done, snooze], intentIdentifiers: [], options: [])
        let existing = await center.notificationCategories()
        center.setNotificationCategories(existing.union([category]))
    }

    private static func trigger(for fireAt: Date, now: Date, calendar: Calendar) -> UNNotificationTrigger {
        let lead = fireAt.timeIntervalSince(now)
        if lead < 120 {
            return UNTimeIntervalNotificationTrigger(timeInterval: max(1, lead), repeats: false)
        }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
        return UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
    }

    /// A mileage reminder that is no longer due can alert again the next time the interval is crossed.
    private static func clearStaleMileageFlags(
        tasks: [MaintenanceTask],
        progressByID: [String: MaintenanceProgress],
        appState: AppState,
        now: Date
    ) {
        let stale = tasks.filter { task in
            task.reminderType == .miles && task.notifiedAt != nil && progressByID[task.id]?.isDue != true
        }.map(\.id)
        appState.clearMaintenanceNotified(ids: stale, now: now)
    }
}

enum MaintenanceSnoozeStore {
    private static let key = "truckorig.maintenance.snooze"

    static func all() -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        return raw.compactMapValues { Date(timeIntervalSince1970: $0) }
    }

    static func set(_ date: Date, for id: String) {
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        raw[id] = date.timeIntervalSince1970
        UserDefaults.standard.set(raw, forKey: key)
    }

    static func clear(_ id: String) {
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        raw.removeValue(forKey: id)
        UserDefaults.standard.set(raw, forKey: key)
    }
}
