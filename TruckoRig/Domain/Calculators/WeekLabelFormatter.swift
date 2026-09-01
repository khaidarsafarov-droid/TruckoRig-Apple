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

    /// `"W32 · Aug 3 – Aug 9, 2025"`.
    public func longLabel(for ref: WeekRef) -> String {
        "W\(ref.weekNumber) · \(label(for: ref))"
    }

    private func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = week.calendar
        formatter.timeZone = week.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }
}
