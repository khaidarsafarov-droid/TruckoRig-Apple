import Foundation

/// First day of a reporting week. Sunday is the US trucking / Amazon Relay settlement week.
public enum WeekStartDay: String, CaseIterable, Codable, Sendable {
    case sunday, monday, tuesday, wednesday, thursday, friday, saturday

    /// `Calendar.firstWeekday` value (1 = Sunday).
    public var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    public var lastCalendarWeekday: Int { (calendarWeekday - 1 + 6) % 7 + 1 }

    public static let `default`: WeekStartDay = .sunday
}

/// A reporting week identified by its number and week-year.
///
/// The week-year is not always the calendar year: 2025-12-28 belongs to week 1 of 2026 on a
/// Sunday-start calendar, and settlement has to follow the week, not the December date.
public struct WeekRef: Equatable, Hashable, Comparable, Codable, Sendable {
    public var weekNumber: Int
    public var year: Int

    public init(weekNumber: Int, year: Int) {
        self.weekNumber = weekNumber
        self.year = year
    }

    public static func < (lhs: WeekRef, rhs: WeekRef) -> Bool {
        (lhs.year, lhs.weekNumber) < (rhs.year, rhs.weekNumber)
    }
}

/// Sun–Sat (configurable) reporting-week math.
///
/// Weeks use `minimumDaysInFirstWeek = 1`, i.e. week 1 is whichever week contains Jan 1. This
/// matches the Android app's `Calendar` configuration rather than ISO-8601, so week numbers stay
/// identical across the two clients for the same load.
public struct TruckingWeek: Sendable {
    public let weekStart: WeekStartDay
    public let calendar: Calendar

    public init(weekStart: WeekStartDay = .default, timeZone: TimeZone = .current) {
        self.weekStart = weekStart
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        calendar.firstWeekday = weekStart.calendarWeekday
        calendar.minimumDaysInFirstWeek = 1
        self.calendar = calendar
    }

    // MARK: - Week identity

    public func week(for date: Date) -> WeekRef {
        let components = calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: date)
        return WeekRef(weekNumber: components.weekOfYear ?? 0, year: components.yearForWeekOfYear ?? 0)
    }

    public func currentWeek(now: Date = Date()) -> WeekRef { week(for: now) }

    public func previousWeek(now: Date = Date()) -> WeekRef {
        shift(week(for: now), by: -1)
    }

    public func shift(_ week: WeekRef, by weeks: Int) -> WeekRef {
        guard let start = startDate(of: week),
              let shifted = calendar.date(byAdding: .weekOfYear, value: weeks, to: start)
        else { return week }
        return self.week(for: shifted)
    }

    // MARK: - Week bounds

    /// Midnight on the first day of the week.
    public func startDate(of week: WeekRef) -> Date? {
        var components = DateComponents()
        components.weekOfYear = week.weekNumber
        components.yearForWeekOfYear = week.year
        components.weekday = weekStart.calendarWeekday
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    /// Midnight on the last day of the week (start of that day, not its end).
    public func endDate(of week: WeekRef) -> Date? {
        guard let start = startDate(of: week) else { return nil }
        return calendar.date(byAdding: .day, value: 6, to: start)
    }

    /// Half-open `[start, endExclusive)` range covering the whole week.
    public func dateRange(of week: WeekRef) -> Range<Date>? {
        guard let start = startDate(of: week),
              let endExclusive = calendar.date(byAdding: .day, value: 7, to: start)
        else { return nil }
        return start..<endExclusive
    }

    public func contains(_ date: Date, in week: WeekRef) -> Bool {
        dateRange(of: week)?.contains(date) ?? false
    }

    /// Noon on the first day of the week — a DST-safe anchor for week pickers.
    public func anchorDate(of week: WeekRef) -> Date? {
        startDate(of: week).flatMap { calendar.date(byAdding: .hour, value: 12, to: $0) }
    }

    // MARK: - Day counts

    /// 1 on the first day of the week … 7 on the last.
    public func daysElapsed(now: Date = Date()) -> Int {
        let weekday = calendar.component(.weekday, from: now)
        return (weekday - weekStart.calendarWeekday + 7) % 7 + 1
    }

    /// Days left including today.
    public func daysRemaining(now: Date = Date()) -> Int {
        let weekday = calendar.component(.weekday, from: now)
        return (weekStart.lastCalendarWeekday - weekday + 7) % 7 + 1
    }

    /// Days the week has been running. Closed weeks count as full 7.
    public func daysActive(in week: WeekRef, now: Date = Date()) -> Int {
        guard week == currentWeek(now: now) else { return 7 }
        return max(1, daysElapsed(now: now))
    }

    /// Days left in the week. Closed weeks return 1 so per-day math never divides by zero.
    public func daysRemaining(in week: WeekRef, now: Date = Date()) -> Int {
        guard week == currentWeek(now: now) else { return 1 }
        return max(1, daysRemaining(now: now))
    }
}
