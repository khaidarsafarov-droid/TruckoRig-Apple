import Foundation

/// Timestamps found in an exported chat log, with where they appeared in the text.
///
/// Drivers paste whole Telegram histories. Each `name, [05.07.2025 10:00]` header tells the parser
/// which year the `MM/DD` schedules below it belong to.
public struct ChatHistoryDates: Sendable {

    private let headers: [(offset: Int, date: Date)]

    private static let bracketPattern = Rx(#"\[(\d{1,2})\.(\d{1,2})\.(\d{4})[,\s]+(\d{1,2}):(\d{2})(?::\d{2})?\]"#, options: [])
    private static let isoPattern = Rx(#"\[(\d{4})-(\d{2})-(\d{2})[,\sT]+(\d{1,2}):(\d{2})(?::\d{2})?\]"#, options: [])

    public init(text: String, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date? {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            return calendar.date(from: components)
        }

        var found: [(Int, Date)] = []
        for match in Self.bracketPattern.matches(in: text) {
            guard let date = makeDate(
                year: Int(match.groupOrEmpty(3)) ?? 0,
                month: Int(match.groupOrEmpty(2)) ?? 0,
                day: Int(match.groupOrEmpty(1)) ?? 0,
                hour: Int(match.groupOrEmpty(4)) ?? 0,
                minute: Int(match.groupOrEmpty(5)) ?? 0
            ) else { continue }
            found.append((text.distance(from: text.startIndex, to: match.range.lowerBound), date))
        }
        for match in Self.isoPattern.matches(in: text) {
            guard let date = makeDate(
                year: Int(match.groupOrEmpty(1)) ?? 0,
                month: Int(match.groupOrEmpty(2)) ?? 0,
                day: Int(match.groupOrEmpty(3)) ?? 0,
                hour: Int(match.groupOrEmpty(4)) ?? 0,
                minute: Int(match.groupOrEmpty(5)) ?? 0
            ) else { continue }
            found.append((text.distance(from: text.startIndex, to: match.range.lowerBound), date))
        }
        headers = found.sorted { $0.0 < $1.0 }.map { (offset: $0.0, date: $0.1) }
    }

    public var isEmpty: Bool { headers.isEmpty }

    /// Reference instant for a block starting at `offset`: the closest header above it.
    public func reference(at offset: Int, fallback: Date) -> Date {
        var result = fallback
        var matched = false
        for header in headers {
            if header.offset <= offset {
                result = header.date
                matched = true
            } else {
                break
            }
        }
        // A block above the first header still belongs to that conversation, so borrow its date
        // rather than falling back to the wall clock.
        if !matched, let first = headers.first { return first.date }
        return result
    }
}
