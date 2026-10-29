import XCTest
@testable import TruckoRig

/// Opening Edit Load and saving without edits must leave the stored trip alone.
@MainActor
final class EditLoadRoundTripTests: XCTestCase {

    func testSaveWithoutEditsKeepsMoneyMilesDatesStopsAndDispute() throws {
        let database = try AppDatabase.ephemeral()
        let repository = LoadRepository(database: database, week: TruckingWeek(weekStart: .sunday, timeZone: TimeZone(secondsFromGMT: 0)!))
        let created = try repository.create(untouchedDraft())
        try repository.addPenalty(to: created, summary: "lumper", amount: 75.25, date: makeDate(2026, 10, 30))

        let before = try XCTUnwrap(database.load(tripId: "T-111HLM7BD"))
        var draft = LoadDraft(load: before).savingUntouchedForm()
        let hasFinish = draft.actualFinishDate != nil
        let finish = draft.actualFinishDate ?? before.lastDeliveryAt ?? Date()
        draft.actualFinishDate = hasFinish ? finish : nil
        XCTAssertTrue(draft.isValid)

        try repository.update(before, with: draft)
        let after = try XCTUnwrap(database.load(tripId: "T-111HLM7BD"))

        XCTAssertEqual(MoneyCents.fromDollars(after.totalRate).cents, MoneyCents.fromDollars(before.totalRate).cents)
        XCTAssertEqual(MoneyCents.fromDollars(after.totalRate).cents, 211_172)
        XCTAssertEqual(after.totalMiles, before.totalMiles)
        XCTAssertEqual(after.deadheadMiles, before.deadheadMiles)
        XCTAssertEqual(after.date, before.date)
        XCTAssertEqual(after.actualFinishDate, before.actualFinishDate)
        XCTAssertEqual(after.pointA, before.pointA)
        XCTAssertEqual(after.pointB, before.pointB)
        XCTAssertEqual(after.isDispute, before.isDispute)
        XCTAssertEqual(after.disputeCompleted, before.disputeCompleted)
        XCTAssertEqual(after.disputeApplyToLoad, before.disputeApplyToLoad)
        XCTAssertEqual(after.disputeAmountApplied, before.disputeAmountApplied)
        XCTAssertEqual(after.disputeResponseDate, before.disputeResponseDate)
        XCTAssertEqual(
            after.disputeAmount.map { MoneyCents.fromDollars($0).cents },
            before.disputeAmount.map { MoneyCents.fromDollars($0).cents }
        )
        XCTAssertEqual(after.equipmentType, before.equipmentType)
        XCTAssertEqual(after.rawMessage, before.rawMessage)
        XCTAssertEqual(after.parsedAt, before.parsedAt)
        XCTAssertEqual(after.stops?.map(stopFacts), before.stops?.map(stopFacts))
        XCTAssertEqual(after.penalties?.map(penaltyFacts), before.penalties?.map(penaltyFacts))
        XCTAssertEqual(after.weekNumber, before.weekNumber)
        XCTAssertEqual(after.year, before.year)
    }

    private func untouchedDraft() -> LoadDraft {
        LoadDraft(
            tripId: "T-111HLM7BD",
            date: makeDate(2026, 10, 29, 6, 30),
            totalRate: 2111.72,
            totalMiles: 714.5,
            stops: [
                StopDraft(
                    type: .pickup,
                    stopNumber: 1,
                    note: "dock 4",
                    facility: "ATL2",
                    city: "Atlanta",
                    state: "GA",
                    scheduledTimeRaw: "10/29 06:30 EDT",
                    scheduledTime: makeDate(2026, 10, 29, 6, 30),
                    timezone: "EDT"
                ),
                StopDraft(
                    type: .delivery,
                    stopNumber: 2,
                    note: "receiver closed at 15:00",
                    facility: "ABE8",
                    city: "Carlisle",
                    state: "PA",
                    scheduledTimeRaw: "10/30 14:00 EDT",
                    scheduledTime: makeDate(2026, 10, 30, 14, 0),
                    timezone: "EDT"
                ),
            ],
            actualFinishDate: makeDate(2026, 10, 30, 15, 0),
            isDispute: true,
            disputeCompleted: false,
            disputeResponseDate: makeDate(2026, 11, 2),
            disputeAmount: 0.05,
            disputeApplyToLoad: false,
            equipmentType: "DRY_VAN",
            deadheadMiles: 45,
            rawMessage: "Trip ID: T-111HLM7BD\nTotal Rate: 2111.72"
        )
    }

    private func stopFacts(_ stop: Stop) -> String {
        [
            stop.type.rawValue,
            "\(stop.stopNumber)",
            stop.facility ?? "",
            stop.city,
            stop.state,
            stop.note ?? "",
            stop.scheduledTimeRaw ?? "",
            stop.timezone ?? "",
            stop.scheduledTime.map { String($0.timeIntervalSince1970) } ?? "",
        ].joined(separator: "|")
    }

    private func penaltyFacts(_ penalty: Penalty) -> String {
        "\(penalty.summary)|\(MoneyCents.fromDollars(penalty.amount).cents)|\(penalty.date.timeIntervalSince1970)"
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
