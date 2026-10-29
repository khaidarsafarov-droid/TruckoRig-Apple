import XCTest
@testable import TruckoRigDomain

final class MaintenanceReminderScheduleTests: XCTestCase {

    private let calendar = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone).calendar
    private let now = makeDate(2026, 10, 28, 11, 0)

    func testDateReminderFiresAtNineOnTheDueMorning() {
        let task = dateTask(due: "2026-11-02")
        let fires = MaintenanceReminderSchedule.plan(
            tasks: [task],
            progressByID: [:],
            now: now,
            calendar: calendar,
            quietEnabled: false,
            quietStartHour: 22,
            quietEndHour: 7,
            snoozeUntil: [:],
            notificationsEnabled: true
        )
        XCTAssertEqual(fires.count, 1)
        XCTAssertEqual(fires[0].identifier, "maint.\(task.id)")
        XCTAssertFalse(fires[0].markNotifiedWhenQueued)
        XCTAssertEqual(calendar.component(.hour, from: fires[0].fireAt), 9)
        XCTAssertEqual(isoDay(fires[0].fireAt), "2026-11-02")
    }

    func testOverdueDateAndDueMileageAlertOnceUntilSnoozed() {
        let overdue = dateTask(due: "2026-10-20", notified: false)
        let already = dateTask(id: "told", due: "2026-10-20", notified: true)
        let oil = milesTask(id: "oil", dueNow: true)
        let waiting = milesTask(id: "tires", dueNow: false)
        let fires = MaintenanceReminderSchedule.plan(
            tasks: [overdue, already, oil.task, waiting.task],
            progressByID: ["oil": oil.progress, "tires": waiting.progress],
            now: now,
            calendar: calendar,
            quietEnabled: false,
            quietStartHour: 22,
            quietEndHour: 7,
            snoozeUntil: [:],
            notificationsEnabled: true
        )
        XCTAssertEqual(Set(fires.map(\.taskID)), [overdue.id, "oil"])
        XCTAssertTrue(fires.allSatisfy(\.markNotifiedWhenQueued))
    }

    func testSnoozeReplacesTheDueAlertAndQuietHoursMoveTheMorning() {
        let task = dateTask(due: "2026-10-20")
        let snooze = makeDate(2026, 10, 29, 8, 0)
        let fires = MaintenanceReminderSchedule.plan(
            tasks: [task],
            progressByID: [:],
            now: now,
            calendar: calendar,
            quietEnabled: true,
            quietStartHour: 22,
            quietEndHour: 7,
            snoozeUntil: [task.id: snooze],
            notificationsEnabled: true
        )
        XCTAssertEqual(fires.count, 1)
        XCTAssertEqual(isoDay(fires[0].fireAt), "2026-10-29")
        XCTAssertFalse(fires[0].markNotifiedWhenQueued)

        let quietMorning = dateTask(id: "quiet", due: "2026-11-02")
        let moved = MaintenanceReminderSchedule.plan(
            tasks: [quietMorning],
            progressByID: [:],
            now: now,
            calendar: calendar,
            quietEnabled: true,
            quietStartHour: 0,
            quietEndHour: 10,
            snoozeUntil: [:],
            notificationsEnabled: true
        )
        XCTAssertEqual(calendar.component(.hour, from: moved[0].fireAt), 10)
    }

    func testDisabledSwitchSchedulesNothing() {
        let fires = MaintenanceReminderSchedule.plan(
            tasks: [dateTask(due: "2026-11-02"), milesTask(id: "oil", dueNow: true).task],
            progressByID: ["oil": milesTask(id: "oil", dueNow: true).progress],
            now: now,
            calendar: calendar,
            quietEnabled: false,
            quietStartHour: 22,
            quietEndHour: 7,
            snoozeUntil: [:],
            notificationsEnabled: false
        )
        XCTAssertTrue(fires.isEmpty)
    }

    func testDoneRecreatesTheNextMilesAndDateOccurrence() {
        let oil = milesTask(id: "oil", dueNow: true).task
        let nextMiles = MaintenanceReminderSchedule.nextTask(after: oil, now: now, calendar: calendar)
        XCTAssertEqual(nextMiles?.reminderType, .miles)
        XCTAssertEqual(nextMiles?.odometerAtStart, 15_000)
        XCTAssertEqual(nextMiles?.intervalMiles, 5_000)
        XCTAssertEqual(nextMiles?.notifiedAt, nil)
        XCTAssertEqual(nextMiles?.isCompleted, false)
        XCTAssertNotEqual(nextMiles?.id, oil.id)

        let dated = dateTask(due: "2026-11-27")
        var spanned = dated
        spanned.startDate = "2026-10-28"
        let nextDate = MaintenanceReminderSchedule.nextTask(after: spanned, now: now, calendar: calendar)
        XCTAssertEqual(nextDate?.startDate, "2026-11-27")
        XCTAssertEqual(nextDate?.dueDate, "2026-12-27")

        let oneShot = dateTask(due: "2026-10-28")
        XCTAssertNil(MaintenanceReminderSchedule.nextTask(after: oneShot, now: now, calendar: calendar))
    }

    private func dateTask(id: String = "date", due: String, notified: Bool = false) -> MaintenanceTask {
        MaintenanceTask(
            id: id,
            title: "Inspection",
            startDate: due,
            reminderType: .date,
            dueDate: due,
            notifiedAt: notified ? 1 : nil
        )
    }

    private func milesTask(id: String, dueNow: Bool) -> (task: MaintenanceTask, progress: MaintenanceProgress) {
        let task = MaintenanceTask(
            id: id,
            title: "Oil",
            startDate: "2026-01-01",
            reminderType: .miles,
            intervalMiles: 5_000,
            odometerAtStart: 10_000
        )
        let progress = MaintenanceProgress(
            task: task,
            milesDrivenSinceStart: dueNow ? 5_100 : 100,
            estimatedOdometer: dueNow ? 15_100 : 10_100,
            targetOdometer: 15_000,
            milesRemaining: dueNow ? 0 : 4_900,
            daysRemaining: nil,
            isDue: dueNow
        )
        return (task, progress)
    }
}
