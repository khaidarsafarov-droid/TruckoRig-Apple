import Foundation

/// One local alert the app should hand to UserNotifications.
///
/// Date reminders fire at 09:00 on the due day. Mileage reminders have no future clock time:
/// they appear only after a launch or a miles update finds them due. A snooze replaces both.
public struct MaintenanceFire: Equatable, Sendable {
    public var taskID: String
    public var title: String
    public var fireAt: Date
    /// True when the alert is for a condition that is already true, so queueing it counts as delivery.
    public var markNotifiedWhenQueued: Bool

    public init(taskID: String, title: String, fireAt: Date, markNotifiedWhenQueued: Bool) {
        self.taskID = taskID
        self.title = title
        self.fireAt = fireAt
        self.markNotifiedWhenQueued = markNotifiedWhenQueued
    }

    public var identifier: String { "maint.\(taskID)" }
}

public enum MaintenanceReminderSchedule {
    public static let alertHour = 9
    public static let snoozeInterval: TimeInterval = 24 * 60 * 60
    public static let immediateLead: TimeInterval = 60

    public static func plan(
        tasks: [MaintenanceTask],
        progressByID: [String: MaintenanceProgress],
        now: Date,
        calendar: Calendar,
        quietEnabled: Bool,
        quietStartHour: Int,
        quietEndHour: Int,
        snoozeUntil: [String: Date],
        notificationsEnabled: Bool
    ) -> [MaintenanceFire] {
        guard notificationsEnabled else { return [] }
        return tasks.compactMap { task in
            guard !task.isCompleted else { return nil }
            if let snooze = snoozeUntil[task.id], snooze > now {
                return fire(
                    task: task,
                    at: snooze,
                    now: now,
                    calendar: calendar,
                    quietEnabled: quietEnabled,
                    quietStartHour: quietStartHour,
                    quietEndHour: quietEndHour,
                    markWhenQueued: false
                )
            }
            switch task.reminderType {
            case .date:
                return dateFire(
                    task: task,
                    now: now,
                    calendar: calendar,
                    quietEnabled: quietEnabled,
                    quietStartHour: quietStartHour,
                    quietEndHour: quietEndHour
                )
            case .miles:
                guard progressByID[task.id]?.isDue == true, task.notifiedAt == nil else { return nil }
                return fire(
                    task: task,
                    at: now.addingTimeInterval(immediateLead),
                    now: now,
                    calendar: calendar,
                    quietEnabled: quietEnabled,
                    quietStartHour: quietStartHour,
                    quietEndHour: quietEndHour,
                    markWhenQueued: true
                )
            }
        }
    }

    /// The following oil change or dated service. A date with no gap between start and due does not repeat.
    public static func nextTask(
        after task: MaintenanceTask,
        now: Date,
        calendar: Calendar
    ) -> MaintenanceTask? {
        let nowMillis = Int64(now.timeIntervalSince1970 * 1000)
        switch task.reminderType {
        case .miles:
            guard let interval = task.intervalMiles, interval > 0 else { return nil }
            let base = task.odometerAtStart ?? 0
            return MaintenanceTask(
                title: task.title,
                startDate: MaintenanceMileage.isoDay(now, calendar: calendar),
                reminderType: .miles,
                intervalMiles: interval,
                odometerAtStart: base + interval,
                createdAt: nowMillis,
                updatedAt: nowMillis
            )
        case .date:
            guard let dueText = task.dueDate,
                  let start = MaintenanceMileage.parseDay(task.startDate, calendar: calendar),
                  let due = MaintenanceMileage.parseDay(dueText, calendar: calendar)
            else { return nil }
            let span = calendar.dateComponents([.day], from: start, to: due).day ?? 0
            guard span > 0, let nextDue = calendar.date(byAdding: .day, value: span, to: due) else { return nil }
            return MaintenanceTask(
                title: task.title,
                startDate: MaintenanceMileage.isoDay(due, calendar: calendar),
                reminderType: .date,
                odometerAtStart: task.odometerAtStart,
                dueDate: MaintenanceMileage.isoDay(nextDue, calendar: calendar),
                createdAt: nowMillis,
                updatedAt: nowMillis
            )
        }
    }

    private static func dateFire(
        task: MaintenanceTask,
        now: Date,
        calendar: Calendar,
        quietEnabled: Bool,
        quietStartHour: Int,
        quietEndHour: Int
    ) -> MaintenanceFire? {
        guard let dueText = task.dueDate,
              let dueDay = MaintenanceMileage.parseDay(dueText, calendar: calendar)
        else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: dueDay)
        parts.hour = alertHour
        parts.minute = 0
        parts.second = 0
        let morning = calendar.date(from: parts) ?? dueDay
        if morning > now {
            return fire(
                task: task,
                at: morning,
                now: now,
                calendar: calendar,
                quietEnabled: quietEnabled,
                quietStartHour: quietStartHour,
                quietEndHour: quietEndHour,
                markWhenQueued: false
            )
        }
        guard task.notifiedAt == nil else { return nil }
        return fire(
            task: task,
            at: now.addingTimeInterval(immediateLead),
            now: now,
            calendar: calendar,
            quietEnabled: quietEnabled,
            quietStartHour: quietStartHour,
            quietEndHour: quietEndHour,
            markWhenQueued: true
        )
    }

    private static func fire(
        task: MaintenanceTask,
        at raw: Date,
        now: Date,
        calendar: Calendar,
        quietEnabled: Bool,
        quietStartHour: Int,
        quietEndHour: Int,
        markWhenQueued: Bool
    ) -> MaintenanceFire? {
        guard let adjusted = QuietHours.adjustedFireDate(
            raw,
            startHour: quietStartHour,
            endHour: quietEndHour,
            enabled: quietEnabled,
            calendar: calendar
        ) else { return nil }
        let fireAt = adjusted < now ? now.addingTimeInterval(immediateLead) : adjusted
        return MaintenanceFire(
            taskID: task.id,
            title: task.title,
            fireAt: fireAt,
            markNotifiedWhenQueued: markWhenQueued
        )
    }
}
