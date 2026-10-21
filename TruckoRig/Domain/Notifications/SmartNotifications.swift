import Foundation

/// Port of Android `QuietHours`. A window that wraps midnight (22 → 7) is quiet overnight.
/// `endHour` is exclusive. `start == end` quiets the whole day, so that window has no end.
public enum QuietHours {
    public static func isActive(nowHour: Int, startHour: Int, endHour: Int, enabled: Bool) -> Bool {
        if !enabled { return false }
        let now = min(23, max(0, nowHour))
        let start = min(23, max(0, startHour))
        let end = min(23, max(0, endHour))
        if start == end { return true }
        if start < end { return now >= start && now < end }
        return now >= start || now < end
    }

    /// Moves `fireAt` to the first minute the quiet window has ended.
    ///
    /// Android `SmartNotificationWorker` returns without posting while `QuietHours.isActive` is
    /// true. iOS has no 24-hour worker to retry that run, so a fire time inside the window is
    /// delivered at `endHour:00` instead of being dropped. An overnight window (start after end)
    /// lands on the next morning when the fire hour is still on the evening side of midnight.
    /// A same-day window lands later that day. A time outside the window, including the exclusive
    /// end hour, is unchanged. `start == end` never leaves the window, so the result is `nil`.
    public static func adjustedFireDate(
        _ fireAt: Date,
        startHour: Int,
        endHour: Int,
        enabled: Bool,
        calendar: Calendar
    ) -> Date? {
        let start = min(23, max(0, startHour))
        let end = min(23, max(0, endHour))
        let hour = calendar.component(.hour, from: fireAt)
        guard isActive(nowHour: hour, startHour: start, endHour: end, enabled: enabled) else {
            return fireAt
        }
        guard start != end else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: fireAt)
        parts.hour = end
        parts.minute = 0
        parts.second = 0
        parts.nanosecond = 0
        guard var endDate = calendar.date(from: parts) else { return fireAt }
        if endDate <= fireAt {
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
        return endDate
    }
}

/// Pure decisions for the 24-hour reminder pass. Port of `SmartNotificationPlanner`.
public struct SmartNotificationPlan: Equatable, Sendable {
    public var notifyMissingPaycheck: Bool
    public var notifyMissingDiesel: Bool
    public var maintenanceDueTitles: [String]

    public var hasAny: Bool {
        notifyMissingPaycheck || notifyMissingDiesel || !maintenanceDueTitles.isEmpty
    }

    public func maintenanceSummaryBody(separator: String = ", ") -> String {
        maintenanceDueTitles.joined(separator: separator)
    }

    public static func plan(
        hasPaycheckForLastWeek: Bool,
        dieselEntriesLastWeek: Int,
        maintenanceDueTitles: [String] = [],
        alreadyNotifiedMissingWeek: Bool = false
    ) -> SmartNotificationPlan {
        SmartNotificationPlan(
            notifyMissingPaycheck: !alreadyNotifiedMissingWeek && !hasPaycheckForLastWeek,
            notifyMissingDiesel: !alreadyNotifiedMissingWeek && dieselEntriesLastWeek <= 0,
            maintenanceDueTitles: maintenanceDueTitles
        )
    }
}

/// Android notification copy. English is `values/strings.xml`, Russian is `values-ru`.
public enum SmartNotificationCopy {
    public static let paycheckIdentifier = "1"
    public static let dieselIdentifier = "2"
    public static let maintenanceIdentifier = "100"
    public static let missingChannel = "truckerload_missing"
    public static let alertsChannel = "truckerload_alerts"
    /// Older Android builds posted one notification per task in 101…130.
    public static let legacyMaintenanceIdentifiers: [String] = (101...130).map(String.init)

    public static func maintenanceTitle(russian: Bool) -> String {
        russian ? "Напоминание ТО" : "Maintenance reminder"
    }

    public static func maintenanceBody(title: String, russian: Bool) -> String {
        russian ? "\(title) — пора обслуживать трак" : "\(title) — time to service the truck"
    }

    public static func maintenanceBody(count: Int, summary: String, russian: Bool) -> String {
        russian ? "\(count) задач: \(summary)" : "\(count) tasks: \(summary)"
    }

    public static func paycheckTitle(russian: Bool) -> String {
        russian ? "Добавьте зарплату" : "Add paycheck"
    }

    public static func dieselTitle(russian: Bool) -> String {
        russian ? "Добавьте дизель" : "Add diesel"
    }

    public static func missingWeekBody(week: Int, russian: Bool) -> String {
        russian ? "Нет данных за неделю \(week)" : "No data for week \(week)"
    }
}

public struct PendingLocalNotification: Equatable, Sendable {
    public var identifier: String
    public var title: String
    public var body: String
    public var channel: String
    public var fireAt: Date

    public init(identifier: String, title: String, body: String, channel: String, fireAt: Date) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.channel = channel
        self.fireAt = fireAt
    }
}

/// What the app should hand to `UNUserNotificationCenter` after one evaluation.
///
/// Android runs `SmartNotificationWorker` about 24 hours after it was scheduled. iOS has no
/// equivalent background worker, so the next fire time is handed to UserNotifications. A fire
/// time inside quiet hours moves to the exclusive end of that window (`QuietHours.adjustedFireDate`)
/// instead of being dropped. `start == end` quiets every hour and is not scheduled.
public struct SmartNotificationDecision: Equatable, Sendable {
    public var notifications: [PendingLocalNotification]
    public var markNotifiedIDs: [String]
    public var recordMissingWeek: Bool
    public var lastRunAt: Date?
    public var evaluatedNow: Bool
    public var suppressedByQuietHours: Bool

    public var cancelIdentifiers: [String] {
        [
            SmartNotificationCopy.paycheckIdentifier,
            SmartNotificationCopy.dieselIdentifier,
            SmartNotificationCopy.maintenanceIdentifier,
        ] + SmartNotificationCopy.legacyMaintenanceIdentifiers
    }
}

public struct SmartNotificationRequest: Sendable {
    public var now: Date
    public var calendar: Calendar
    public var lastRunAt: Date?
    /// When false, this is the first evaluation: anchor `lastRunAt` to `now` and fire one period later.
    public var quietEnabled: Bool
    public var quietStartHour: Int
    public var quietEndHour: Int
    public var allowMissingWeek: Bool
    public var allowMaintenance: Bool
    public var hasPaycheckForLastWeek: Bool
    public var dieselEntriesLastWeek: Int
    public var alreadyNotifiedMissingWeek: Bool
    public var missingWeekNumber: Int
    /// Tasks `MaintenanceMileage.shouldNotify` already accepted, in display order.
    public var maintenanceDue: [(id: String, title: String)]
    public var russian: Bool

    public init(
        now: Date,
        calendar: Calendar,
        lastRunAt: Date?,
        quietEnabled: Bool,
        quietStartHour: Int,
        quietEndHour: Int,
        allowMissingWeek: Bool,
        allowMaintenance: Bool,
        hasPaycheckForLastWeek: Bool,
        dieselEntriesLastWeek: Int,
        alreadyNotifiedMissingWeek: Bool,
        missingWeekNumber: Int,
        maintenanceDue: [(id: String, title: String)],
        russian: Bool
    ) {
        self.now = now
        self.calendar = calendar
        self.lastRunAt = lastRunAt
        self.quietEnabled = quietEnabled
        self.quietStartHour = quietStartHour
        self.quietEndHour = quietEndHour
        self.allowMissingWeek = allowMissingWeek
        self.allowMaintenance = allowMaintenance
        self.hasPaycheckForLastWeek = hasPaycheckForLastWeek
        self.dieselEntriesLastWeek = dieselEntriesLastWeek
        self.alreadyNotifiedMissingWeek = alreadyNotifiedMissingWeek
        self.missingWeekNumber = missingWeekNumber
        self.maintenanceDue = maintenanceDue
        self.russian = russian
    }
}

public enum SmartNotificationEngine {
    public static let period: TimeInterval = 24 * 60 * 60

    public static func evaluate(_ request: SmartNotificationRequest) -> SmartNotificationDecision {
        let anchor = request.lastRunAt ?? request.now
        let next = anchor.addingTimeInterval(period)
        let dueNow = request.lastRunAt != nil && request.now.addingTimeInterval(0.5) >= next
        let rawFireAt = dueNow ? request.now : next
        guard let fireAt = QuietHours.adjustedFireDate(
            rawFireAt,
            startHour: request.quietStartHour,
            endHour: request.quietEndHour,
            enabled: request.quietEnabled,
            calendar: request.calendar
        ) else {
            return SmartNotificationDecision(
                notifications: [],
                markNotifiedIDs: [],
                recordMissingWeek: false,
                lastRunAt: dueNow ? request.now : anchor,
                evaluatedNow: dueNow,
                suppressedByQuietHours: true
            )
        }

        let titles = request.allowMaintenance ? request.maintenanceDue.map(\.title) : []
        let plan = SmartNotificationPlan.plan(
            hasPaycheckForLastWeek: request.hasPaycheckForLastWeek,
            dieselEntriesLastWeek: request.dieselEntriesLastWeek,
            maintenanceDueTitles: titles,
            alreadyNotifiedMissingWeek: request.alreadyNotifiedMissingWeek || !request.allowMissingWeek
        )
        var notifications: [PendingLocalNotification] = []
        if request.allowMissingWeek && plan.notifyMissingPaycheck {
            notifications.append(PendingLocalNotification(
                identifier: SmartNotificationCopy.paycheckIdentifier,
                title: SmartNotificationCopy.paycheckTitle(russian: request.russian),
                body: SmartNotificationCopy.missingWeekBody(week: request.missingWeekNumber, russian: request.russian),
                channel: SmartNotificationCopy.missingChannel,
                fireAt: fireAt
            ))
        }
        if request.allowMissingWeek && plan.notifyMissingDiesel {
            notifications.append(PendingLocalNotification(
                identifier: SmartNotificationCopy.dieselIdentifier,
                title: SmartNotificationCopy.dieselTitle(russian: request.russian),
                body: SmartNotificationCopy.missingWeekBody(week: request.missingWeekNumber, russian: request.russian),
                channel: SmartNotificationCopy.missingChannel,
                fireAt: fireAt
            ))
        }
        if !plan.maintenanceDueTitles.isEmpty {
            let body: String
            if plan.maintenanceDueTitles.count == 1 {
                body = SmartNotificationCopy.maintenanceBody(title: plan.maintenanceDueTitles[0], russian: request.russian)
            } else {
                body = SmartNotificationCopy.maintenanceBody(
                    count: plan.maintenanceDueTitles.count,
                    summary: plan.maintenanceSummaryBody(),
                    russian: request.russian
                )
            }
            notifications.append(PendingLocalNotification(
                identifier: SmartNotificationCopy.maintenanceIdentifier,
                title: SmartNotificationCopy.maintenanceTitle(russian: request.russian),
                body: body,
                channel: SmartNotificationCopy.alertsChannel,
                fireAt: fireAt
            ))
        }
        let mark = notifications.contains { $0.identifier == SmartNotificationCopy.maintenanceIdentifier }
            ? request.maintenanceDue.map(\.id)
            : []
        let recordWeek = notifications.contains {
            $0.identifier == SmartNotificationCopy.paycheckIdentifier
                || $0.identifier == SmartNotificationCopy.dieselIdentifier
        }
        return SmartNotificationDecision(
            notifications: notifications,
            markNotifiedIDs: mark,
            recordMissingWeek: recordWeek,
            lastRunAt: dueNow ? request.now : anchor,
            evaluatedNow: dueNow,
            suppressedByQuietHours: false
        )
    }
}
