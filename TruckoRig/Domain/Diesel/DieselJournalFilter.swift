import Foundation

/// One diesel row the journal can slice by week or calendar day.
public struct DieselJournalRow: Equatable, Sendable {
    public var id: String
    public var recordedAt: Date
    public var sourceFileName: String?

    public init(id: String, recordedAt: Date, sourceFileName: String? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.sourceFileName = sourceFileName
    }
}

/// Week and calendar-day slices of diesel fills.
///
/// One spreadsheet is one diesel week: every row from that file follows the week of its earliest
/// fill. A lone fill, or a file whose dates span more than seven days, stays on its own date.
public enum DieselJournalFilter {

    public static func reportingWeek(
        of row: DieselJournalRow,
        among rows: [DieselJournalRow],
        week: TruckingWeek
    ) -> WeekRef {
        week.week(for: fileAnchor(row, among: rows, week: week)?.recordedAt ?? row.recordedAt)
    }

    public static func forWeek(
        _ rows: [DieselJournalRow],
        weekNumber: Int,
        year: Int,
        week: TruckingWeek
    ) -> [DieselJournalRow] {
        rows.filter { row in
            let ref = reportingWeek(of: row, among: rows, week: week)
            return ref.weekNumber == weekNumber && ref.year == year
        }
        .sorted { $0.recordedAt > $1.recordedAt }
    }

    public static func forDate(_ rows: [DieselJournalRow], iso: String, week: TruckingWeek) -> [DieselJournalRow] {
        rows.filter { isoDay($0.recordedAt, week: week) == iso }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    private static func fileAnchor(
        _ row: DieselJournalRow,
        among rows: [DieselJournalRow],
        week: TruckingWeek
    ) -> DieselJournalRow? {
        guard let file = row.sourceFileName?.trimmingCharacters(in: .whitespacesAndNewlines), !file.isEmpty else {
            return nil
        }
        let siblings = rows.filter { $0.sourceFileName == file }
        guard siblings.count >= 2, spansAtMostOneWeek(siblings, week: week) else { return nil }
        return siblings.min { $0.recordedAt < $1.recordedAt }
    }

    private static func spansAtMostOneWeek(_ rows: [DieselJournalRow], week: TruckingWeek) -> Bool {
        let dates = rows.map { isoDay($0.recordedAt, week: week) }.filter { $0.count >= 10 }.sorted()
        guard let first = dates.first, let last = dates.last, dates.count >= 2 else { return true }
        guard let start = date(fromISO: first, week: week), let end = date(fromISO: last, week: week) else { return false }
        let days = week.calendar.dateComponents([.day], from: start, to: end).day ?? 99
        return days <= 6
    }

    static func isoDay(_ date: Date, week: TruckingWeek) -> String {
        let parts = week.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func date(fromISO iso: String, week: TruckingWeek) -> Date? {
        let pieces = iso.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var components = DateComponents()
        components.year = pieces[0]
        components.month = pieces[1]
        components.day = pieces[2]
        return week.calendar.date(from: components)
    }
}
