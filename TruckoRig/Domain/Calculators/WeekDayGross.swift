import Foundation

/// One load's gross, dated the way Android files it: pickup day, else the finish that pulled it
/// into this reporting week.
public struct AttributedLoad: Equatable, Sendable {
    public var pickup: Date
    public var finish: Date?
    public var rate: Double

    public init(pickup: Date, finish: Date?, rate: Double) {
        self.pickup = pickup
        self.finish = finish
        self.rate = rate
    }
}

/// Puts every load that belongs to a reporting week onto one day inside that week.
///
/// Android stores the pickup day in `load.date` and sums `strftime('%w', date)`. A Saturday
/// pickup that delivers on Sunday is filed in the Sunday week, so its pickup day is outside
/// that week — the gross then lands on the finish day, or the week would not add up.
public enum WeekDayGross {

    public static func day(pickup: Date, finish: Date?, week: TruckingWeek, ref: WeekRef) -> Date? {
        guard let range = week.dateRange(of: ref) else { return nil }
        let calendar = week.calendar
        let pickupDay = calendar.startOfDay(for: pickup)
        if range.contains(pickupDay) { return pickupDay }
        if let finish {
            let finishDay = calendar.startOfDay(for: finish)
            if range.contains(finishDay) { return finishDay }
        }
        return calendar.startOfDay(for: range.lowerBound)
    }

    /// SQLite `strftime('%w')`: Sunday is 0.
    public static func sqliteWeekday(_ date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - 1 + 7) % 7
    }

    public static func centsBySqliteWeekday(
        loads: [AttributedLoad],
        week: TruckingWeek,
        ref: WeekRef
    ) -> [Int: Int64] {
        var buckets: [Int: Int64] = [:]
        for load in loads {
            guard let day = day(pickup: load.pickup, finish: load.finish, week: week, ref: ref) else { continue }
            let key = sqliteWeekday(day, calendar: week.calendar)
            buckets[key, default: 0] += MoneyCents.fromDollars(load.rate).cents
        }
        return buckets
    }

    public static func bookedDollars(_ centsBySqliteWeekday: [Int: Int64]) -> Double {
        MoneyCents(cents: centsBySqliteWeekday.values.reduce(0, +)).dollars
    }
}
