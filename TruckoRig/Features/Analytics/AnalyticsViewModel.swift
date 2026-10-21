import Foundation
import Observation

/// Money, routes and charts for «Мои цифры».
///
/// The window is the last eight reporting weeks, which is what the approved stats mockup draws
/// (W36–W43). Paycheck and diesel stay separate: the screen never subtracts them.
@Observable
final class AnalyticsViewModel {

    static let weekCount = 8

    func page(
        loads: [Load],
        paychecks: [Paycheck],
        diesel: [Diesel],
        calendar: TruckingWeek,
        now: Date = Date()
    ) -> AnalyticsPage {
        let summaries = loads.map(\.summary)
        let weeks = AnalyticsCalculator.weeklySeries(
            loads: summaries,
            weeks: Self.weekCount,
            calendar: calendar,
            now: now
        )
        let start = weeks.compactMap { calendar.startDate(of: $0.week) }.min()
        let end = calendar.dateRange(of: calendar.currentWeek(now: now))?.upperBound ?? now
        let range: Range<Date>? = start.map { $0..<end }
        let inWindow = summaries.filter { summary in
            guard let range, let date = summary.chartDate else { return range == nil }
            return range.contains(date)
        }
        return AnalyticsPage(
            finance: PeriodFinanceCalculator.calculate(
                paychecks: paychecks.map {
                    PaycheckSlice(
                        amount: $0.amount,
                        weekNumber: $0.weekNumber,
                        year: $0.year,
                        date: $0.date,
                        updatedAt: $0.updatedAt
                    )
                },
                diesel: diesel.map {
                    DieselSlice(
                        gallons: $0.gallons,
                        totalCost: $0.totalCost,
                        pricePerGallon: $0.pricePerGallon,
                        date: $0.date
                    )
                },
                range: range
            ),
            routes: AnalyticsCalculator.topRoutes(loads: inWindow, limit: 5),
            daily: AnalyticsCalculator.dailyDistribution(loads: inWindow, calendar: calendar),
            weeks: weeks
        )
    }
}

struct AnalyticsPage: Equatable {
    var finance: PeriodFinance
    var routes: [RouteStat]
    var daily: [WeekdayGross]
    var weeks: [WeeklyPoint]
}
