import Foundation
import SwiftData

/// Refiles every row into reporting weeks after the week-start preference changes.
///
/// Week numbers are cached on each row so the journal and goal screens can query them directly.
/// Changing the week start invalidates every one of those caches at once — without this, a driver
/// switching from Sunday to Monday would see weeks that no longer match their settlements.
@MainActor
enum WeekReindexer {

    struct Report: Equatable {
        var loads = 0
        var paychecks = 0
    }

    @discardableResult
    static func reindex(in context: ModelContext, week: TruckingWeek) throws -> Report {
        var report = Report()

        for load in try context.fetch(FetchDescriptor<Load>()) {
            let before = WeekRef(weekNumber: load.weekNumber, year: load.year)
            load.refreshDerivedFields(week: week)
            if WeekRef(weekNumber: load.weekNumber, year: load.year) != before { report.loads += 1 }
        }

        for paycheck in try context.fetch(FetchDescriptor<Paycheck>()) {
            let before = WeekRef(weekNumber: paycheck.weekNumber, year: paycheck.year)
            paycheck.refreshWeek(week: week)
            if WeekRef(weekNumber: paycheck.weekNumber, year: paycheck.year) != before { report.paychecks += 1 }
        }

        try context.save()
        return report
    }
}
