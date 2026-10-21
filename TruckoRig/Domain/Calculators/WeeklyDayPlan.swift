import Foundation

/// One row of the weekly goal day plan. Port of Android `DayPlanRow`.
public struct DayPlanRow: Equatable, Sendable {
    public enum Status: String, Sendable {
        case pastMet
        case pastMissed
        case today
        case future
    }

    public var date: Date
    /// `strftime('%w')`: Sunday is 0.
    public var sqliteWeekday: Int
    public var gross: MoneyCents
    public var status: Status
    /// Rounded actual ÷ daily need, in percent. Zero when no daily need is set.
    public var planPercent: Int
    /// 0…1 for the today ring.
    public var planFraction: Double

    public init(
        date: Date,
        sqliteWeekday: Int,
        gross: MoneyCents,
        status: Status,
        planPercent: Int,
        planFraction: Double
    ) {
        self.date = date
        self.sqliteWeekday = sqliteWeekday
        self.gross = gross
        self.status = status
        self.planPercent = planPercent
        self.planFraction = planFraction
    }
}

/// Seven rows for the reporting week, in week-start order.
///
/// Gross is keyed by SQLite weekday so it matches Android `LoadDao.getDailyDistribution`
/// (`strftime('%w', date)`, Sunday = 0) summed from `load.date`.
public enum WeeklyDayPlan {

    public static func rows(
        weekStart: Date,
        today: Date,
        grossCentsBySqliteWeekday: [Int: Int64],
        dailyNeeded: MoneyCents,
        calendar: Calendar
    ) -> [DayPlanRow] {
        let start = calendar.startOfDay(for: weekStart)
        let todayDay = calendar.startOfDay(for: today)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            let sqlite = (weekday - 1 + 7) % 7
            let gross = MoneyCents(cents: grossCentsBySqliteWeekday[sqlite] ?? 0)
            let status: DayPlanRow.Status
            if date < todayDay {
                status = met(gross, needed: dailyNeeded) ? .pastMet : .pastMissed
            } else if date > todayDay {
                status = .future
            } else {
                status = .today
            }
            return DayPlanRow(
                date: date,
                sqliteWeekday: sqlite,
                gross: gross,
                status: status,
                planPercent: percentOf(gross, needed: dailyNeeded),
                planFraction: fractionOf(gross, needed: dailyNeeded)
            )
        }
    }

    public static func percentOf(_ gross: MoneyCents, needed: MoneyCents) -> Int {
        if needed.cents <= 0 { return gross.cents > 0 ? 100 : 0 }
        let rounded = (gross.cents * 100 + needed.cents / 2) / needed.cents
        return Int(max(0, rounded))
    }

    private static func met(_ gross: MoneyCents, needed: MoneyCents) -> Bool {
        if needed.cents <= 0 { return gross.cents > 0 }
        return gross.cents >= needed.cents
    }

    private static func fractionOf(_ gross: MoneyCents, needed: MoneyCents) -> Double {
        if needed.cents <= 0 { return gross.cents > 0 ? 1 : 0 }
        return min(1, max(0, Double(gross.cents) / Double(needed.cents)))
    }
}

/// Chips under the goal editor. Port of `UxMotivation.suggestedWeeklyGoals`.
public enum SuggestedWeeklyGoals {

    public static func amounts(closedWeekGross: Double) -> [Double] {
        guard closedWeekGross > 0 else { return [5_000, 6_000, 7_000] }
        let anchor = (closedWeekGross / 500).rounded(.toNearestOrAwayFromZero) * 500
        let base = max(1_000, anchor)
        return [base - 1_000, base, base + 500]
    }

    /// `10000 → 10K`, `11500 → $11,500`.
    public static func chip(_ amount: Double) -> String {
        let whole = Int64(amount.rounded(.toNearestOrAwayFromZero))
        if whole % 1_000 == 0 {
            return "\(whole / 1_000)K"
        }
        return USMoneyFormat.currency(Double(whole))
    }
}

/// Pure input rules for the weekly gross editor. Port of `WeeklyGoalInputValidator`.
public enum WeeklyGoalInput {

    public static func sanitize(_ value: String) -> String {
        String(value.filter { $0.isNumber || $0 == "." || $0 == "," })
    }

    public static func parseGoalAmount(_ value: String) -> Double? {
        DecimalInput.parse(value)
    }

    public static func format(_ amount: Double) -> String {
        if amount <= 0 { return "" }
        if amount.truncatingRemainder(dividingBy: 1) == 0 { return String(Int64(amount)) }
        return String(amount)
    }
}
