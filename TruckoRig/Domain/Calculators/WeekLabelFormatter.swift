import Foundation

/// Renders `"Aug 3 – Aug 9, 2025"` style captions for a reporting week.
public struct WeekLabelFormatter: Sendable {
    private let week: TruckingWeek
    private let locale: Locale

    public init(week: TruckingWeek = TruckingWeek(), locale: Locale = .current) {
        self.week = week
        self.locale = locale
    }

    public func label(for ref: WeekRef) -> String {
        guard let start = week.startDate(of: ref), let end = week.endDate(of: ref) else {
            return "W\(ref.weekNumber) \(ref.year)"
        }
        let calendar = week.calendar
        let startYear = calendar.component(.year, from: start)
        return "\(monthDay(start)) – \(monthDay(end)), \(startYear)"
    }

    /// `"August 2025"` — the month a week mostly falls in.
    ///
    /// Measured from midweek, not the first day, so a week running Aug 31 – Sep 6 is filed under
    /// September the way a driver would describe it.
    public func monthLabel(for ref: WeekRef) -> String {
        guard let start = week.startDate(of: ref),
              let midweek = week.calendar.date(byAdding: .day, value: 3, to: start)
        else { return String(ref.year) }

        return DateFormatCache.string(from: midweek, template: "MMMMy", locale: locale, calendar: week.calendar)
    }

    /// Month caption to show above `ref`, or `nil` when `previous` is already in the same month.
    ///
    /// Lets a flat list of weeks read as year → month → week without nesting sections.
    public func monthMarker(for ref: WeekRef, after previous: WeekRef?) -> String? {
        let label = monthLabel(for: ref)
        guard let previous else { return label }
        return monthLabel(for: previous) == label ? nil : label
    }

    private func monthDay(_ date: Date) -> String {
        DateFormatCache.string(from: date, template: "MMMd", locale: locale, calendar: week.calendar)
            .replacingOccurrences(of: ".", with: "")
    }
}
