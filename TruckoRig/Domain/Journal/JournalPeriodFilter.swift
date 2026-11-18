import Foundation

/// Journal slices. Names match Android `LoadFilter`, plus the iOS unfinished row.
public enum JournalSlice: String, CaseIterable, Sendable {
    case all
    case disputes
    case unfinished
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case calendarWeek
    case onDate
    case dateRange
}

public enum JournalPeriodFilter {
    public static func includes(
        date: Date,
        activeDispute: Bool,
        unfinished: Bool,
        slice: JournalSlice,
        selectedDay: Date,
        week: TruckingWeek,
        rangeStart: Date = Date(),
        rangeEnd: Date = Date(),
        now: Date = Date(),
        end: Date? = nil,
        reportingWeek: WeekRef? = nil
    ) -> Bool {
        let calendar = week.calendar
        switch slice {
        case .all:
            return true
        case .disputes:
            return activeDispute
        case .unfinished:
            return unfinished
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
            return contains(yesterday, from: date, through: end, calendar: calendar)
        case .thisWeek:
            return filedWeek(of: date, week: week, override: reportingWeek) == week.currentWeek(now: now)
        case .lastWeek:
            return filedWeek(of: date, week: week, override: reportingWeek) == week.previousWeek(now: now)
        case .thisMonth:
            return overlapsMonth(of: now, from: date, through: end, calendar: calendar)
        case .calendarWeek:
            return filedWeek(of: date, week: week, override: reportingWeek) == week.week(for: selectedDay)
        case .onDate:
            return contains(selectedDay, from: date, through: end, calendar: calendar)
        case .dateRange:
            return overlaps(rangeStart, rangeEnd, from: date, through: end, calendar: calendar)
        }
    }

    /// Pickup through finish, one entry per calendar day. A missing finish is the pickup day.
    public static func activeDays(from start: Date, through end: Date?, calendar: Calendar, limit: Int = 62) -> [Date] {
        let first = calendar.startOfDay(for: min(start, end ?? start))
        let last = calendar.startOfDay(for: max(start, end ?? start))
        var days: [Date] = []
        var cursor = first
        while cursor <= last && days.count < limit {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        if days.last != last { days.append(last) }
        return days
    }

    private static func filedWeek(of date: Date, week: TruckingWeek, override: WeekRef?) -> WeekRef {
        override ?? week.week(for: date)
    }

    private static func contains(_ day: Date, from start: Date, through end: Date?, calendar: Calendar) -> Bool {
        let target = calendar.startOfDay(for: day)
        let first = calendar.startOfDay(for: min(start, end ?? start))
        let last = calendar.startOfDay(for: max(start, end ?? start))
        return target >= first && target <= last
    }

    private static func overlaps(_ rangeStart: Date, _ rangeEnd: Date, from start: Date, through end: Date?, calendar: Calendar) -> Bool {
        let rangeFirst = calendar.startOfDay(for: min(rangeStart, rangeEnd))
        let rangeLast = calendar.startOfDay(for: max(rangeStart, rangeEnd))
        let first = calendar.startOfDay(for: min(start, end ?? start))
        let last = calendar.startOfDay(for: max(start, end ?? start))
        return first <= rangeLast && rangeFirst <= last
    }

    private static func overlapsMonth(of now: Date, from start: Date, through end: Date?, calendar: Calendar) -> Bool {
        let first = calendar.startOfDay(for: min(start, end ?? start))
        let last = calendar.startOfDay(for: max(start, end ?? start))
        if calendar.isDate(first, equalTo: now, toGranularity: .month) { return true }
        if calendar.isDate(last, equalTo: now, toGranularity: .month) { return true }
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return false }
        return first < nextMonth && last >= monthStart
    }
}

/// Trip ID, city and date lookup for the journal field.
///
/// A leading `#` is ignored so the id printed on the card (`#T-…`) matches the stored id.
/// Dates match each ISO day the load is out (`2026-10-29`), `M/d`, `d.MM`, and the row label.
public enum JournalSearch {
    public static func matches(
        query: String,
        tripId: String,
        places: [String],
        isoDates: [String],
        displayDates: [String]
    ) -> Bool {
        var needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        if needle.hasPrefix("#") {
            needle = String(needle.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !needle.isEmpty else { return true }
        let haystacks = [tripId] + isoDates + places + displayDates
        return haystacks.contains { contains($0, needle) }
    }

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
