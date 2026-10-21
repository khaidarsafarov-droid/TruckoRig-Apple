import XCTest
@testable import TruckoRigDomain

final class MaintenanceLogicTests: XCTestCase {

    private let week = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone)
    private var today: Date { makeDate(2026, 7, 28, 12, 0) }

    func testMilesNotDueUntilIntervalReached() {
        let task = milesTask(interval: 5_000, odometer: 100_000, start: "2026-01-01")
        let mid = MaintenanceMileage.progress(task: task, milesDrivenSinceStart: 2_000, today: today, week: week)
        XCTAssertFalse(mid.isDue)
        XCTAssertEqual(mid.milesRemaining ?? -1, 3_000, accuracy: 0.01)
        XCTAssertEqual(mid.estimatedOdometer ?? -1, 102_000, accuracy: 0.01)

        let due = MaintenanceMileage.progress(task: task, milesDrivenSinceStart: 5_000, today: today, week: week)
        XCTAssertTrue(due.isDue)
        XCTAssertEqual(due.milesRemaining ?? -1, 0, accuracy: 0.01)
        XCTAssertTrue(MaintenanceMileage.shouldNotify(due))
    }

    func testDateDueOnOrAfterDueDate() {
        let task = MaintenanceTask(
            title: "Inspection",
            startDate: "2026-01-01",
            reminderType: .date,
            dueDate: "2026-07-01"
        )
        let before = MaintenanceMileage.progress(
            task: task,
            milesDrivenSinceStart: 0,
            today: makeDate(2026, 6, 30, 12, 0),
            week: week
        )
        XCTAssertFalse(before.isDue)
        XCTAssertEqual(before.daysRemaining, 1)

        let onDay = MaintenanceMileage.progress(
            task: task,
            milesDrivenSinceStart: 0,
            today: makeDate(2026, 7, 1, 12, 0),
            week: week
        )
        XCTAssertTrue(onDay.isDue)
        XCTAssertEqual(onDay.daysRemaining, 0)
    }

    func testShouldNotifySkipsCompletedOrAlreadyNotified() {
        var task = milesTask(interval: 100, odometer: 0, start: "2026-01-01")
        task.isCompleted = true
        let progress = MaintenanceMileage.progress(task: task, milesDrivenSinceStart: 200, today: today, week: week)
        XCTAssertTrue(progress.isDue)
        XCTAssertFalse(MaintenanceMileage.shouldNotify(progress))

        task.isCompleted = false
        task.notifiedAt = 10
        let notified = MaintenanceMileage.progress(task: task, milesDrivenSinceStart: 200, today: today, week: week)
        XCTAssertFalse(MaintenanceMileage.shouldNotify(notified))
    }

    func testSameDayFinishCountsAndEarlierFinishDoesNot() {
        let loads = [
            load("T-OLD", 5_000, "2026-07-20", "2026-07-22"),
            load("T-SAME-DAY", 1_778, "2026-07-24", "2026-07-24"),
            load("T-B", 1_502, "2026-07-28", "2026-07-28"),
        ]
        let snap = MaintenanceMileage.calculate(
            baseOdometer: 878_030,
            targetInterval: 20_000,
            serviceDate: "2026-07-24",
            loads: loads,
            today: today,
            week: week
        )
        XCTAssertEqual(snap.totalDrivenMiles, 3_280)
        XCTAssertEqual(snap.currentOdometer, 881_310)
        XCTAssertEqual(snap.targetOdometer, 898_030)
        XCTAssertEqual(snap.remainingMiles, 16_720)
        XCTAssertEqual(snap.loadCount, 2)
        XCTAssertFalse(snap.isUrgent)
    }

    func testFinishDateNotStartWhenTripSpansService() {
        let snap = MaintenanceMileage.calculate(
            baseOdometer: 878_030,
            targetInterval: 20_000,
            serviceDate: "2026-07-24",
            loads: [load("T-SPAN", 1_502, "2026-07-22", "2026-07-28")],
            today: today,
            week: week
        )
        XCTAssertEqual(snap.milesSinceService, 1_502)
        XCTAssertEqual(snap.remainingMiles, 18_498)
    }

    func testFarFutureMisdatedEndIsDroppedAndSameWeekAheadOfTheClockCounts() {
        let future = MaintenanceMileage.calculate(
            baseOdometer: 100_000,
            targetInterval: 5_000,
            serviceDate: "2026-07-24",
            loads: [
                load("T-FUT", 200_000, "2026-12-01", "2026-12-01"),
                load("T-OK", 800, "2026-07-26", "2026-07-26"),
            ],
            today: today,
            week: week
        )
        XCTAssertEqual(future.milesSinceService, 800)

        let midWeek = makeDate(2026, 7, 22, 12, 0)
        let sameWeek = MaintenanceMileage.calculate(
            baseOdometer: 100_000,
            targetInterval: 20_000,
            serviceDate: "2026-07-20",
            loads: [load("T-WEEK", 1_502, "2026-07-25", "2026-07-25")],
            today: midWeek,
            week: week
        )
        XCTAssertEqual(sameWeek.milesSinceService, 1_502)
        XCTAssertEqual(sameWeek.loadCount, 1)
    }

    func testMilesStayWholeNumbersAndDuplicateTripIdsCountOnce() {
        XCTAssertEqual(MaintenanceMileage.milesAsLong(1_778.4), 1_778)
        XCTAssertEqual(MaintenanceMileage.milesAsLong(20_000), 15_000)
        let snap = MaintenanceMileage.calculate(
            baseOdometer: 10,
            targetInterval: 100,
            serviceDate: "2026-07-24",
            loads: [
                load("A", 1_500, "2026-07-25", "2026-07-25"),
                load("A", 1_778, "2026-07-26", "2026-07-26"),
            ],
            today: today,
            week: week
        )
        XCTAssertEqual(snap.milesSinceService, 1_500)
        XCTAssertEqual(snap.loadCount, 1)
    }

    func testProgressMapsTheOilChangeScreenshot() {
        let task = MaintenanceTask(
            title: "Замена масло",
            startDate: "2026-07-24",
            reminderType: .miles,
            intervalMiles: 20_000,
            odometerAtStart: 878_030
        )
        let progress = MaintenanceMileage.progress(
            task: task,
            loads: [load("T-113Q6BJDT", 1_502, "2026-07-28", "2026-07-28")],
            today: today,
            week: week
        )
        XCTAssertEqual(progress.milesDrivenSinceStart, 1_502, accuracy: 0.01)
        XCTAssertEqual(progress.estimatedOdometer ?? 0, 879_532, accuracy: 0.01)
        XCTAssertEqual(progress.targetOdometer ?? 0, 898_030, accuracy: 0.01)
        XCTAssertEqual(progress.milesRemaining ?? 0, 18_498, accuracy: 0.01)
        XCTAssertEqual(progress.loadsCounted, 1)
        XCTAssertFalse(progress.isDue)
        XCTAssertEqual(progress.progressFraction, 1_502 / 20_000, accuracy: 0.0001)
    }

    func testVisitsGroupByDatePhotoAndCreatedAt() {
        let created: Int64 = 1_700_000_000_000
        let entries = [
            line("1", "VALVE ADJUSTMENT", 500, created),
            line("2", "OIL FILTER", 43.12, created),
        ]
        let visits = MaintenanceVisits.group(entries)
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits[0].total, 543.12, accuracy: 0.01)
        XCTAssertEqual(visits[0].ids, ["1", "2"])
        XCTAssertEqual(visits[0].shopName, "Shop")

        let separate = MaintenanceVisits.group([
            line("1", "Oil", 80, 10),
            line("2", "Tires", 400, 20, date: "2026-08-24"),
        ])
        XCTAssertEqual(separate.count, 2)
        XCTAssertEqual(separate[0].lines[0].description, "Oil")
        XCTAssertEqual(separate[1].lines[0].description, "Tires")
    }

    func testArchiveDraftValidationAndTaskDraft() {
        var draft = MaintenanceArchiveDraft(serviceDate: "2026-08-25", lines: [
            MaintenanceArchiveLineDraft(description: "", amount: ""),
        ])
        XCTAssertEqual(draft.validationError(), .emptyLines)
        draft.lines = [MaintenanceArchiveLineDraft(description: "Oil", amount: "-1")]
        XCTAssertEqual(draft.validationError(), .invalidAmount)
        draft.lines = [MaintenanceArchiveLineDraft(description: "Oil", amount: "43.12")]
        let entries = draft.toEntries(createdAt: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].amount.cents, 4_312)

        let bad = MaintenanceTaskDraft(
            startDate: "2026-07-24",
            intervalMiles: "0",
            odometerAtStart: "10",
            dueDate: "2026-08-24"
        )
        XCTAssertEqual(bad.validated(nowMillis: 1), .failure(.emptyTitle))
        var miles = bad
        miles.title = "Oil"
        XCTAssertEqual(miles.validated(nowMillis: 1), .failure(.invalidInterval))
    }

    func testLegacyStubBecomesAMilesTaskAndAnArchiveLine() {
        let imported = MaintenanceLegacyImport.convert(
            MaintenanceLegacyImport.Stub(
                id: "task-1",
                title: "Oil",
                dueOdometer: 5_000,
                cost: 80,
                notes: "filters",
                updatedAtMillis: 50
            ),
            fallbackStartDate: "2026-07-01"
        )
        XCTAssertEqual(imported.task.reminderType, .miles)
        XCTAssertEqual(imported.task.intervalMiles ?? 0, 5_000, accuracy: 0.01)
        XCTAssertEqual(imported.task.odometerAtStart ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(imported.archive?.description, "filters")
        XCTAssertEqual(imported.archive?.amount.dollars ?? 0, 80, accuracy: 0.01)
    }

    private func milesTask(interval: Double, odometer: Double, start: String) -> MaintenanceTask {
        MaintenanceTask(
            title: "Oil",
            startDate: start,
            reminderType: .miles,
            intervalMiles: interval,
            odometerAtStart: odometer,
            createdAt: 1
        )
    }

    private func load(_ tripId: String, _ miles: Double, _ date: String, _ finish: String) -> MaintenanceMileage.LoadInput {
        MaintenanceMileage.LoadInput(tripId: tripId, id: tripId, miles: miles, date: date, actualFinishDate: finish)
    }

    private func line(
        _ id: String,
        _ description: String,
        _ amount: Double,
        _ createdAt: Int64,
        date: String = "2026-08-25"
    ) -> MaintenanceArchiveEntry {
        MaintenanceArchiveEntry(
            id: id,
            serviceName: "Shop",
            serviceDate: date,
            description: description,
            amount: MoneyCents.fromDollars(amount),
            createdAt: createdAt
        )
    }
}

final class SmartNotificationTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = testTimeZone
        return calendar
    }

    func testQuietHoursWrapsPastMidnight() {
        XCTAssertFalse(QuietHours.isActive(nowHour: 12, startHour: 22, endHour: 7, enabled: false))
        XCTAssertTrue(QuietHours.isActive(nowHour: 23, startHour: 22, endHour: 7, enabled: true))
        XCTAssertTrue(QuietHours.isActive(nowHour: 6, startHour: 22, endHour: 7, enabled: true))
        XCTAssertFalse(QuietHours.isActive(nowHour: 7, startHour: 22, endHour: 7, enabled: true))
        XCTAssertTrue(QuietHours.isActive(nowHour: 15, startHour: 9, endHour: 17, enabled: true))
        XCTAssertFalse(QuietHours.isActive(nowHour: 17, startHour: 9, endHour: 17, enabled: true))
        XCTAssertTrue(QuietHours.isActive(nowHour: 3, startHour: 10, endHour: 10, enabled: true))
    }

    func testPlannerMatchesAndroidCases() {
        let empty = SmartNotificationPlan.plan(hasPaycheckForLastWeek: false, dieselEntriesLastWeek: 0)
        XCTAssertTrue(empty.notifyMissingPaycheck)
        XCTAssertTrue(empty.notifyMissingDiesel)
        XCTAssertTrue(empty.hasAny)

        let present = SmartNotificationPlan.plan(hasPaycheckForLastWeek: true, dieselEntriesLastWeek: 2)
        XCTAssertFalse(present.hasAny)

        let already = SmartNotificationPlan.plan(
            hasPaycheckForLastWeek: false,
            dieselEntriesLastWeek: 0,
            alreadyNotifiedMissingWeek: true
        )
        XCTAssertFalse(already.notifyMissingPaycheck)
        XCTAssertFalse(already.notifyMissingDiesel)

        let maintenance = SmartNotificationPlan.plan(
            hasPaycheckForLastWeek: true,
            dieselEntriesLastWeek: 1,
            maintenanceDueTitles: ["Oil change", "Tires"]
        )
        XCTAssertEqual(maintenance.maintenanceDueTitles, ["Oil change", "Tires"])
        XCTAssertEqual(maintenance.maintenanceSummaryBody(), "Oil change, Tires")
    }

    func testFirstRunSchedulesOnePeriodLaterAndQuietHoursSuppress() {
        let now = makeDate(2026, 7, 28, 15, 0)
        let first = SmartNotificationEngine.evaluate(request(now: now, lastRunAt: nil))
        XCTAssertFalse(first.evaluatedNow)
        XCTAssertEqual(first.notifications.map(\.identifier), ["1", "2", "100"])
        XCTAssertEqual(first.notifications[0].fireAt, now.addingTimeInterval(24 * 60 * 60))
        XCTAssertEqual(first.notifications[0].title, "Add paycheck")
        XCTAssertEqual(first.notifications[0].body, "No data for week 30")
        XCTAssertEqual(first.notifications[2].title, "Maintenance reminder")
        XCTAssertEqual(first.notifications[2].body, "Oil — time to service the truck")
        XCTAssertEqual(first.notifications[2].channel, "truckerload_alerts")
        XCTAssertEqual(first.markNotifiedIDs, ["oil"])
        XCTAssertTrue(first.recordMissingWeek)
        XCTAssertEqual(first.lastRunAt, now)

        var quiet = request(now: now, lastRunAt: nil)
        quiet.quietEnabled = true
        quiet.quietStartHour = 14
        quiet.quietEndHour = 18
        let suppressed = SmartNotificationEngine.evaluate(quiet)
        XCTAssertTrue(suppressed.notifications.isEmpty)
        XCTAssertTrue(suppressed.suppressedByQuietHours)
        XCTAssertFalse(suppressed.recordMissingWeek)
    }

    func testDueRunPostsNowAndASecondRunDoesNotRepeatARecordedWeek() {
        let now = makeDate(2026, 7, 29, 15, 0)
        let last = now.addingTimeInterval(-24 * 60 * 60)
        let decision = SmartNotificationEngine.evaluate(request(now: now, lastRunAt: last, russian: true))
        XCTAssertTrue(decision.evaluatedNow)
        XCTAssertEqual(decision.notifications[2].body, "Oil — пора обслуживать трак")
        XCTAssertEqual(decision.notifications[0].title, "Добавьте зарплату")
        XCTAssertEqual(decision.lastRunAt, now)

        var repeatRun = request(now: now, lastRunAt: last, russian: true)
        repeatRun.alreadyNotifiedMissingWeek = true
        repeatRun.maintenanceDue = [
            ("oil", "Oil"),
            ("tires", "Tires"),
        ]
        let bundled = SmartNotificationEngine.evaluate(repeatRun)
        XCTAssertEqual(bundled.notifications.map(\.identifier), ["100"])
        XCTAssertEqual(bundled.notifications[0].body, "2 задач: Oil, Tires")
        XCTAssertFalse(bundled.recordMissingWeek)
    }

    func testDisabledTogglesDropThoseReminders() {
        var request = request(now: makeDate(2026, 7, 29, 15, 0), lastRunAt: makeDate(2026, 7, 28, 15, 0))
        request.allowMissingWeek = false
        request.allowMaintenance = false
        let decision = SmartNotificationEngine.evaluate(request)
        XCTAssertTrue(decision.notifications.isEmpty)
        XCTAssertTrue(decision.evaluatedNow)
    }

    private func request(now: Date, lastRunAt: Date?, russian: Bool = false) -> SmartNotificationRequest {
        SmartNotificationRequest(
            now: now,
            calendar: calendar,
            lastRunAt: lastRunAt,
            quietEnabled: false,
            quietStartHour: 22,
            quietEndHour: 7,
            allowMissingWeek: true,
            allowMaintenance: true,
            hasPaycheckForLastWeek: false,
            dieselEntriesLastWeek: 0,
            alreadyNotifiedMissingWeek: false,
            missingWeekNumber: 30,
            maintenanceDue: [("oil", "Oil")],
            russian: russian
        )
    }
}

final class ServiceReceiptParserTests: XCTestCase {

    func testPrefersGrandTotalOverLineItemsAndSubtotal() {
        let text = """
        Love's Truck Tire Care
        Oil change + filters
        Date: 07/15/2026
        Labor $999.00
        Filter $45.00
        Subtotal $180.00
        Tax $20.00
        Grand Total: $200.00
        Thank you
        """
        let result = ServiceReceiptParser.parse(text, defaultDate: "2026-01-01")
        XCTAssertEqual(result.amount ?? 0, 200, accuracy: 0.01)
        XCTAssertEqual(result.date, "2026-07-15")
        XCTAssertTrue(result.serviceName?.localizedCaseInsensitiveContains("Love") == true)
        XCTAssertEqual(result.descriptionHint, "Oil change + filters")
    }

    func testRussianItogoAndInvoiceLines() {
        let russian = """
        Автосервис Север
        Замена масла
        Дата: 15.07.2026
        Итого: 450.50
        """
        let parsed = ServiceReceiptParser.parse(russian, defaultDate: "2026-01-01")
        XCTAssertEqual(parsed.amount ?? 0, 450.50, accuracy: 0.01)
        XCTAssertEqual(parsed.date, "2026-07-15")
        XCTAssertEqual(parsed.serviceName, "Автосервис Север")
        XCTAssertEqual(parsed.descriptionHint, "Замена масла")

        let invoice = """
        Invoice Date: 08/25/2026
        Due Date: 08/25/2026
        Item Description Unit Price Quantity Tax Amount
        VALVE ADJUSTMENT 500.00 1.00 500.00
        OIL FILTER 43.12 1.00 43.12
        FUEL FILTER 92.31 1.00 92.31
        OIL 15.40 198.21 1.00 198.21
        PM IOL CHANGE 180.00 1.00 180.00
        FILTER AIR MOUNT 24.11 2.00 48.22
        SHOP SUPLIES 23.00 1.00 23.00
        Subtotal 1084.86
        Total 1084.86
        Amount Paid 0.00
        Balance Due 1084.86
        """
        let rows = ServiceReceiptParser.parse(invoice, defaultDate: "2026-01-01")
        XCTAssertEqual(rows.amount ?? 0, 1084.86, accuracy: 0.01)
        XCTAssertEqual(rows.date, "2026-08-25")
        XCTAssertEqual(rows.lineItems.count, 7)
        XCTAssertEqual(rows.lineItems[0].description, "VALVE ADJUSTMENT")
        XCTAssertEqual(rows.lineItems[0].amount, 500, accuracy: 0.01)
        XCTAssertEqual(rows.lineItems[3].description, "OIL 15.40")
        XCTAssertEqual(rows.lineItems[3].amount, 198.21, accuracy: 0.01)
        XCTAssertEqual(rows.lineItems[5].description, "FILTER AIR MOUNT")
        XCTAssertEqual(rows.lineItems[5].amount, 48.22, accuracy: 0.01)
    }

    func testBlankReceiptKeepsTheDefaultDate() {
        let result = ServiceReceiptParser.parse("   ", defaultDate: "2026-07-26")
        XCTAssertNil(result.amount)
        XCTAssertEqual(result.date, "2026-07-26")
        XCTAssertTrue(result.lineItems.isEmpty)
    }
}
