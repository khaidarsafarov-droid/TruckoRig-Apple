import Foundation
import Observation

/// Range and aggregation choices for the analytics screen.
@Observable
final class AnalyticsViewModel {

    enum Range: Int, CaseIterable, Identifiable {
        case fourWeeks = 4
        case twelveWeeks = 12
        case yearToDate = 52

        var id: Int { rawValue }

        var title: LocalizedStringResource {
            switch self {
            case .fourWeeks: return "analytics.range.4"
            case .twelveWeeks: return "analytics.range.12"
            case .yearToDate: return "analytics.range.52"
            }
        }
    }

    var range: Range = .twelveWeeks

    func summaries(from loads: [Load], calendar: TruckingWeek, now: Date = Date()) -> [LoadSummary] {
        let cutoff = calendar.shift(calendar.currentWeek(now: now), by: -(range.rawValue - 1))
        guard let start = calendar.startDate(of: cutoff) else { return loads.map(\.summary) }
        return loads.filter { $0.date >= start }.map(\.summary)
    }

    func weeklySeries(from loads: [Load], calendar: TruckingWeek, locale: Locale = .current, now: Date = Date()) -> [WeeklyPoint] {
        AnalyticsCalculator.weeklySeries(
            loads: summaries(from: loads, calendar: calendar, now: now),
            weeks: range.rawValue,
            calendar: calendar,
            locale: locale,
            now: now
        )
    }

    func stateRevenue(from loads: [Load], calendar: TruckingWeek, now: Date = Date()) -> [StateRevenue] {
        AnalyticsCalculator.stateRevenue(loads: summaries(from: loads, calendar: calendar, now: now))
    }

    func topRoutes(from loads: [Load], calendar: TruckingWeek, now: Date = Date()) -> [RouteStat] {
        AnalyticsCalculator.topRoutes(loads: summaries(from: loads, calendar: calendar, now: now))
    }

    func totals(from loads: [Load], calendar: TruckingWeek, now: Date = Date()) -> LoadTotals {
        LoadTotals.of(summaries(from: loads, calendar: calendar, now: now))
    }
}
