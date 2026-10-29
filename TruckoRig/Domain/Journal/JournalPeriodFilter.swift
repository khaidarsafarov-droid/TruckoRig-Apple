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
}

public enum JournalPeriodFilter {
    public static func includes(
        date: Date,
        activeDispute: Bool,
        unfinished: Bool,
        slice: JournalSlice,
        selectedDay: Date,
        week: TruckingWeek,
        now: Date = Date()
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
            return calendar.isDate(date, inSameDayAs: yesterday)
        case .thisWeek:
            return week.week(for: date) == week.currentWeek(now: now)
        case .lastWeek:
            return week.week(for: date) == week.previousWeek(now: now)
        case .thisMonth:
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .calendarWeek:
            return week.week(for: date) == week.week(for: selectedDay)
        case .onDate:
            return calendar.isDate(date, inSameDayAs: selectedDay)
        }
    }
}
