import Foundation
import Observation
import SwiftUI

/// «Мои цифры». Windows match Android `AnalyticsPeriod`: 12 weeks, 6 months, all time.
@Observable
final class AnalyticsViewModel {

    enum Period: String, CaseIterable, Identifiable {
        case twelveWeeks
        case sixMonths
        case allTime

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .twelveWeeks: return "analytics.period.12"
            case .sixMonths: return "analytics.period.6"
            case .allTime: return "analytics.period.all"
            }
        }
    }

    var period: Period = .twelveWeeks

    func page(
        loads: [Load],
        paychecks: [Paycheck],
        diesel: [Diesel],
        calendar: TruckingWeek,
        locale: Locale = AppLocale.locale,
        now: Date = Date()
    ) -> AnalyticsPage {
        let summaries = loads.map(\.summary)
        let count = weekCount(summaries: summaries, calendar: calendar, now: now)
        let weeks = AnalyticsCalculator.weeklySeries(
            loads: summaries,
            weeks: count,
            calendar: calendar,
            locale: locale,
            now: now
        )
        let start = period == .allTime ? nil : weeks.compactMap { calendar.startDate(of: $0.week) }.min()
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
                        discountPricePerGallon: $0.discountPricePerGallon,
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

    private func weekCount(summaries: [LoadSummary], calendar: TruckingWeek, now: Date) -> Int {
        switch period {
        case .twelveWeeks: return 12
        case .sixMonths: return 26
        case .allTime:
            let current = calendar.currentWeek(now: now)
            guard let earliest = summaries.compactMap(\.chartDate).min() else { return 12 }
            var cursor = current
            var count = 1
            let start = calendar.week(for: earliest)
            while cursor > start, count < 260 {
                cursor = calendar.shift(cursor, by: -1)
                count += 1
            }
            return count
        }
    }
}

struct AnalyticsPage: Equatable {
    var finance: PeriodFinance
    var routes: [RouteStat]
    var daily: [WeekdayGross]
    var weeks: [WeeklyPoint]
}
