import XCTest
@testable import TruckoRigDomain

/// Totals, chronological order, and the plain-text layout of a period report.
final class PeriodReportTests: XCTestCase {

    private let week = TruckingWeek(weekStart: .sunday, timeZone: testTimeZone)
    private let generated = makeDate(2026, 11, 21, 9)

    private var ref: WeekRef { week.week(for: makeDate(2026, 11, 16)) }

    func testWeekNumberMatchesTheHomeCard() {
        XCTAssertEqual(ref.weekNumber, 47)
        XCTAssertEqual(ref.year, 2026)
        XCTAssertEqual(isoDay(week.startDate(of: ref)), "2026-11-15")
        XCTAssertEqual(isoDay(week.endDate(of: ref)), "2026-11-21")
    }

    func testWeekTotalsExcludeOtherPeriodsAndKeepLoadedEmptyMiles() {
        let report = englishWeek()
        let totals = report.totals

        XCTAssertEqual(totals.gross, 891)
        XCTAssertEqual(totals.loadCount, 2)
        XCTAssertEqual(totals.loadedMiles, 300)
        XCTAssertEqual(totals.emptyMiles, 31)
        XCTAssertEqual(totals.drivenMiles, 331)
        XCTAssertEqual(totals.fuel, 80)
        XCTAssertEqual(totals.fuelGallons, 20)
        XCTAssertEqual(totals.expenses, 15)
        XCTAssertEqual(totals.penalties, 10)
        XCTAssertEqual(totals.net, 786)
        XCTAssertEqual(totals.goalTarget, 12_000)
        XCTAssertEqual(Int(totals.goalPercent.rounded()), 7)
        XCTAssertEqual(report.loads.map(\.tripId), ["T-100", "T-200"])
        XCTAssertEqual(report.loads.map(\.number), [1, 2])
        XCTAssertFalse(report.loads.contains { $0.tripId == "T-OUT" })
        XCTAssertEqual(report.fileStem, "TruckoRig-week-47-2026")
    }

    func testReportingWeekWinsOverTheCalendarDay() {
        let insideDatesOtherWeek = load(
            trip: "T-DATE",
            rate: 50,
            loaded: 10,
            empty: 0,
            on: makeDate(2026, 11, 16),
            weekRef: WeekRef(weekNumber: 1, year: 2020)
        )
        let outsideDatesThisWeek = load(
            trip: "T-FILED",
            rate: 70,
            loaded: 10,
            empty: 0,
            on: makeDate(2026, 1, 4),
            weekRef: ref
        )
        let report = build(
            loads: [insideDatesOtherWeek, outsideDatesThisWeek],
            fuel: [],
            expenses: [],
            goal: 0
        )

        XCTAssertEqual(report.loads.map(\.tripId), ["T-FILED"])
        XCTAssertEqual(report.totals.gross, 70)
    }

    func testLoadsStayInChronologicalOrderAndTieBreakOnTripId() {
        let later = load(trip: "T-LATER", rate: 10, loaded: 1, empty: 0, on: makeDate(2026, 11, 20))
        let early = load(trip: "T-EARLY", rate: 10, loaded: 1, empty: 0, on: makeDate(2026, 11, 16))
        let bee = load(trip: "T-B", rate: 10, loaded: 1, empty: 0, on: makeDate(2026, 11, 18, 15))
        let aye = load(trip: "T-A", rate: 10, loaded: 1, empty: 0, on: makeDate(2026, 11, 18, 8))
        let report = build(loads: [later, bee, early, aye], fuel: [], expenses: [], goal: 0)

        XCTAssertEqual(report.loads.map(\.tripId), ["T-EARLY", "T-A", "T-B", "T-LATER"])
        XCTAssertEqual(report.loads.map(\.number), [1, 2, 3, 4])
    }

    func testEnglishTextIsHeaderThenSummaryThenNumberedLoads() {
        let report = englishWeek()
        let text = PeriodReportText.render(report)
        let range = WeekLabelFormatter(week: week, locale: Locale(identifier: "en_US")).label(for: ref)

        XCTAssertEqual(report.periodTitle, "Week 47 · \(range)")
        XCTAssertEqual(report.summary.map(\.label), [
            "Gross revenue",
            "Number of loads",
            "Miles",
            "Loaded miles",
            "Empty miles",
            "Average rate",
            "Fuel",
            "Expenses",
            "Penalties",
            "Net",
            "Goal",
            "Goal progress",
        ])
        XCTAssertEqual(report.loads[0].lines.map(\.label), [
            "Route",
            "Load #",
            "Miles",
            "Loaded miles",
            "Empty miles",
            "Rate",
            "Rate per mile",
            "Status",
            "Source",
            "Equipment",
            "Notes",
            "Penalties",
        ])
        XCTAssertEqual(report.loads[1].lines.map(\.label), [
            "Route",
            "Load #",
            "Miles",
            "Loaded miles",
            "Empty miles",
            "Rate",
            "Rate per mile",
            "Status",
            "Source",
        ])

        let markers = [
            "TruckoRig\n",
            "Driver: Khaidar Safarov\n",
            "Period: Week 47 · \(range)\n",
            "Summary\n",
            "Gross revenue: $891.00\n",
            "Number of loads: 2\n",
            "Miles: 331 mi\n",
            "Loaded miles: 300 mi\n",
            "Empty miles: 31 mi\n",
            "Average rate: $2.69/mi\n",
            "Fuel: $80.00 · 20 gal\n",
            "Expenses: $15.00\n",
            "Penalties: $10.00\n",
            "Net: $786.00\n",
            "Goal: $12,000.00\n",
            "Goal progress: 7% ($891.00 of $12,000.00)\n",
            "Loads\n",
            "1. ",
            "Route: Dallas, TX → Chicago, IL\n",
            "Load #: T-100\n",
            "Miles: 220 mi\n",
            "Rate: $600.00\n",
            "Rate per mile: $2.73/mi\n",
            "Status: Delivered\n",
            "Source: Amazon Relay\n",
            "Equipment: Dry van\n",
            "Notes: Dock 4\n",
            "Penalties: Late fee $10.00\n",
            "\n------------\n\n",
            "2. ",
            "Route: Chicago, IL → Detroit, MI\n",
            "Load #: T-200\n",
            "Status: In progress\n",
            "Source: Manual\n",
            "Only on this device",
        ]
        assertInOrder(markers, in: text)
        XCTAssertFalse(text.contains("T-OUT"))
        XCTAssertFalse(text.contains("$999"))
        XCTAssertFalse(text.contains("$50.00"))
        XCTAssertFalse(text.contains("$40.00"))
        XCTAssertTrue(text.hasSuffix("Only on this device"))
    }

    func testRussianTextUsesRussianLabelsInTheSameOrder() {
        let report = build(
            loads: [sampleLoads().0, sampleLoads().1],
            fuel: sampleFuel(),
            expenses: sampleExpenses(),
            goal: 12_000,
            language: .russian,
            driver: "Хайдар Сафаров"
        )
        let text = PeriodReportText.render(report)
        assertInOrder([
            "Водитель: Хайдар Сафаров",
            "Период: Неделя 47 · ",
            "Сводка",
            "Валовая выручка: $891.00",
            "Число грузов: 2",
            "Мили: 331 mi",
            "Топливо: $80.00 · 20 гал",
            "Расходы: $15.00",
            "Штрафы: $10.00",
            "Чистыми: $786.00",
            "Прогресс цели: 7% ($891.00 из $12,000.00)",
            "Грузы",
            "1. ",
            "Маршрут: Dallas, TX → Chicago, IL",
            "№ груза: T-100",
            "Статус: Доставлен",
            "Источник: Amazon Relay",
            "Оборудование: Сухой фургон",
            "Заметки: Dock 4",
            "2. ",
            "Статус: В пути",
            "Источник: Вручную",
            "Только на этом устройстве",
        ], in: text)
        XCTAssertFalse(text.contains("Summary"))
        XCTAssertFalse(text.contains("Driver:"))
        XCTAssertFalse(text.contains("T-OUT"))
    }

    func testEmptyPeriodKeepsTheHeaderAndSaysThereAreNoLoads() {
        let report = build(loads: [], fuel: sampleFuel().filter { $0.totalCost == 50 }, expenses: [], goal: 0)
        let text = PeriodReportText.render(report)

        XCTAssertEqual(report.totals.gross, 0)
        XCTAssertEqual(report.totals.loadCount, 0)
        XCTAssertEqual(report.totals.drivenMiles, 0)
        XCTAssertEqual(report.totals.net, 0)
        XCTAssertEqual(report.totals.goalTarget, 0)
        XCTAssertTrue(report.loads.isEmpty)
        XCTAssertNil(report.driverName)
        XCTAssertFalse(report.summary.map(\.label).contains("Goal"))
        XCTAssertEqual(report.summary.first { $0.label == "Average rate" }?.value, "—")
        assertInOrder([
            "TruckoRig\n",
            "Period: ",
            "Summary\n",
            "Gross revenue: $0.00\n",
            "Number of loads: 0\n",
            "Loads\n",
            "No loads in this period.\n",
            "Only on this device",
        ], in: text)
        XCTAssertFalse(text.contains("\n1. "))
        XCTAssertFalse(text.contains("Driver:"))
    }

    func testMonthIncludesOverlappingLoadsAndScalesTheGoal() {
        let october = PeriodReportLoadInput(
            tripId: "T-OCT",
            rate: 999,
            loadedMiles: 10,
            emptyMiles: 0,
            filedOn: makeDate(2026, 10, 10),
            pickupAt: makeDate(2026, 10, 10),
            deliveryAt: makeDate(2026, 10, 12),
            weekNumber: 1,
            year: 2026
        )
        let crossing = PeriodReportLoadInput(
            tripId: "T-CROSS",
            rate: 100,
            loadedMiles: 40,
            emptyMiles: 0,
            filedOn: makeDate(2026, 10, 30),
            pickupAt: makeDate(2026, 10, 30),
            deliveryAt: makeDate(2026, 11, 2),
            weekNumber: 1,
            year: 2026,
            origin: "Austin, TX",
            destination: "Dallas, TX",
            isDispute: true
        )
        let inside = load(trip: "T-NOV", rate: 200, loaded: 80, empty: 5, on: makeDate(2026, 11, 16))
        let report = build(
            scope: .month(year: 2026, month: 11),
            loads: [october, inside, crossing],
            fuel: [
                PeriodReportFuelFill(totalCost: 30, gallons: 0, date: makeDate(2026, 11, 3)),
                PeriodReportFuelFill(totalCost: 90, gallons: 10, date: makeDate(2026, 10, 3)),
            ],
            expenses: [PeriodReportExpense(amount: 12, date: makeDate(2026, 11, 20))],
            goal: 1_000
        )

        XCTAssertEqual(report.loads.map(\.tripId), ["T-CROSS", "T-NOV"])
        XCTAssertEqual(report.totals.gross, 300)
        XCTAssertEqual(report.totals.fuel, 30)
        XCTAssertEqual(report.totals.expenses, 12)
        XCTAssertEqual(report.totals.net, 258)
        XCTAssertEqual(report.totals.goalTarget, 5_000)
        XCTAssertEqual(report.fileStem, "TruckoRig-2026-11")
        XCTAssertEqual(report.loads[0].lines.first { $0.label == "Status" }?.value, "Dispute open")
        XCTAssertTrue(report.periodTitle.contains("2026"))
        let text = PeriodReportText.render(report)
        XCTAssertLessThan(text.range(of: "Summary")!.lowerBound, text.range(of: "Loads")!.lowerBound)
        XCTAssertLessThan(text.range(of: "1. ")!.lowerBound, text.range(of: "2. ")!.lowerBound)
        XCTAssertFalse(text.contains("T-OCT"))
    }

    func testKilometersRenameDistanceAndFuelVolume() {
        let report = build(
            loads: [sampleLoads().0, sampleLoads().1],
            fuel: sampleFuel(),
            expenses: sampleExpenses(),
            goal: 0,
            system: .kilometers
        )
        let text = PeriodReportText.render(report)

        XCTAssertTrue(report.summary.contains { $0.label == "Kilometers" && $0.value.hasSuffix(" km") })
        XCTAssertTrue(report.summary.contains { $0.label == "Loaded kilometers" })
        XCTAssertTrue(report.summary.contains { $0.label == "Empty kilometers" })
        XCTAssertEqual(report.summary.first { $0.label == "Average rate" }?.value, "$1.67/km")
        XCTAssertTrue(report.summary.contains { $0.label == "Fuel" && $0.value.contains(" L") })
        XCTAssertFalse(text.contains(" mi"))
        XCTAssertFalse(text.contains("/mi"))
        XCTAssertEqual(report.loads[0].lines.first { $0.label == "Rate per kilometer" }?.value, "$1.69/km")
    }

    func testBlankOptionalFieldsAreLeftOut() {
        let bare = load(trip: "  ", rate: 40, loaded: 0, empty: 0, on: makeDate(2026, 11, 18))
        let report = build(loads: [bare], fuel: [], expenses: [], goal: 0, driver: "   ")

        XCTAssertNil(report.driverName)
        XCTAssertFalse(report.loads[0].lines.contains { $0.label == "Route" })
        XCTAssertFalse(report.loads[0].lines.contains { $0.label == "Load #" })
        XCTAssertFalse(report.loads[0].lines.contains { $0.label == "Equipment" })
        XCTAssertFalse(report.loads[0].lines.contains { $0.label == "Notes" })
        XCTAssertFalse(report.loads[0].lines.contains { $0.label == "Penalties" })
        XCTAssertEqual(report.loads[0].lines.first { $0.label == "Rate per mile" }?.value, "—")
    }

    func testScopeFollowsTheDayInsideTheWeekOrMonth() {
        let day = makeDate(2026, 11, 18)
        let weekScope = PeriodReportBuilder.scope(kind: .week, containing: day, week: week)
        let monthScope = PeriodReportBuilder.scope(kind: .month, containing: day, week: week)

        XCTAssertEqual(weekScope, .week(ref))
        XCTAssertEqual(monthScope, .month(year: 2026, month: 11))
    }

    private func englishWeek() -> PeriodReport {
        let pair = sampleLoads()
        return build(
            loads: [pair.1, outsideLoad(), pair.0],
            fuel: sampleFuel(),
            expenses: sampleExpenses(),
            goal: 12_000,
            driver: "Khaidar Safarov"
        )
    }

    private func sampleLoads() -> (PeriodReportLoadInput, PeriodReportLoadInput) {
        let first = load(
            trip: "T-100",
            rate: 600,
            loaded: 200,
            empty: 20,
            on: makeDate(2026, 11, 16, 8),
            delivery: makeDate(2026, 11, 17, 15),
            origin: "Dallas, TX",
            destination: "Chicago, IL",
            equipment: "DRY_VAN",
            source: .relay,
            notes: ["Dock 4"],
            penalties: [PeriodReportPenalty(summary: "Late fee", amount: 10)]
        )
        let second = load(
            trip: "T-200",
            rate: 291,
            loaded: 100,
            empty: 11,
            on: makeDate(2026, 11, 18, 9),
            origin: "Chicago, IL",
            destination: "Detroit, MI"
        )
        return (first, second)
    }

    private func outsideLoad() -> PeriodReportLoadInput {
        load(
            trip: "T-OUT",
            rate: 999,
            loaded: 500,
            empty: 10,
            on: makeDate(2026, 10, 2),
            weekRef: WeekRef(weekNumber: 40, year: 2026),
            origin: "Miami, FL",
            destination: "Atlanta, GA"
        )
    }

    private func sampleFuel() -> [PeriodReportFuelFill] {
        [
            PeriodReportFuelFill(totalCost: 80, gallons: 20, date: makeDate(2026, 11, 17, 7)),
            PeriodReportFuelFill(totalCost: 50, gallons: 12, date: makeDate(2026, 10, 1, 7)),
        ]
    }

    private func sampleExpenses() -> [PeriodReportExpense] {
        [
            PeriodReportExpense(amount: 15, date: makeDate(2026, 11, 18, 12)),
            PeriodReportExpense(amount: 40, date: makeDate(2026, 12, 1, 12)),
        ]
    }

    private func build(
        scope: PeriodReportScope? = nil,
        loads: [PeriodReportLoadInput],
        fuel: [PeriodReportFuelFill],
        expenses: [PeriodReportExpense],
        goal: Double,
        language: PeriodReportLanguage = .english,
        system: MeasurementSystem = .miles,
        driver: String = ""
    ) -> PeriodReport {
        PeriodReportBuilder.build(
            PeriodReportRequest(
                driverName: driver,
                scope: scope ?? .week(ref),
                loads: loads,
                fuel: fuel,
                expenses: expenses,
                weeklyGoal: goal,
                generatedAt: generated,
                language: language,
                measurementSystem: system,
                week: week
            )
        )
    }

    private func load(
        trip: String,
        rate: Double,
        loaded: Double,
        empty: Double,
        on day: Date,
        delivery: Date? = nil,
        weekRef: WeekRef? = nil,
        origin: String = "",
        destination: String = "",
        equipment: String? = nil,
        source: LoadSourceTag = .manual,
        notes: [String] = [],
        penalties: [PeriodReportPenalty] = []
    ) -> PeriodReportLoadInput {
        let filed = weekRef ?? ref
        return PeriodReportLoadInput(
            tripId: trip,
            rate: rate,
            loadedMiles: loaded,
            emptyMiles: empty,
            filedOn: day,
            pickupAt: day,
            deliveryAt: delivery,
            weekNumber: filed.weekNumber,
            year: filed.year,
            origin: origin,
            destination: destination,
            equipmentCode: equipment,
            source: source,
            notes: notes,
            penalties: penalties
        )
    }

    private func assertInOrder(_ markers: [String], in text: String, file: StaticString = #filePath, line: UInt = #line) {
        var search = text.startIndex
        for marker in markers {
            guard let found = text.range(of: marker, range: search..<text.endIndex) else {
                XCTFail("Missing \(marker) after \(text.distance(from: text.startIndex, to: search)) characters:\n\(text)", file: file, line: line)
                return
            }
            search = found.upperBound
        }
    }
}
