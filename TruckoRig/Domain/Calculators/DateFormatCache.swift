import Foundation

/// Built-once `DateFormatter`s for the Domain layer.
///
/// A `DateFormatter` costs far more to build than to use, and the journal, reports and widget ask
/// for the same few patterns on every pass. Formatters are keyed by pattern, locale, calendar and
/// time zone, configured once and never changed afterwards. Every call formats or parses while
/// holding the lock, so a shared formatter is never touched from two threads at once.
enum DateFormatCache {

    private enum Kind: Hashable {
        case pattern(String)
        case template(String)
        case styles(DateFormatter.Style, DateFormatter.Style)
    }

    private struct Key: Hashable {
        let kind: Kind
        let locale: Locale
        let calendar: Calendar
        let timeZone: TimeZone
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var formatters: [Key: DateFormatter] = [:]
        private let limit = 128

        func withFormatter<T>(_ key: Key, _ body: (DateFormatter) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            if let existing = formatters[key] { return body(existing) }
            let formatter = DateFormatter()
            formatter.locale = key.locale
            formatter.calendar = key.calendar
            formatter.timeZone = key.timeZone
            switch key.kind {
            case .pattern(let pattern):
                formatter.dateFormat = pattern
            case .template(let template):
                formatter.setLocalizedDateFormatFromTemplate(template)
            case .styles(let date, let time):
                formatter.dateStyle = date
                formatter.timeStyle = time
            }
            if formatters.count >= limit { formatters.removeAll() }
            formatters[key] = formatter
            return body(formatter)
        }
    }

    private static let store = Store()

    /// `dateFormat` pattern such as `yyyy-MM-dd`.
    static func string(
        from date: Date,
        pattern: String,
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String {
        let key = Key(kind: .pattern(pattern), locale: locale, calendar: calendar, timeZone: timeZone)
        return store.withFormatter(key) { $0.string(from: date) }
    }

    /// Parses with the same cached formatter as `string(from:pattern:...)`.
    static func date(
        from text: String,
        pattern: String,
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Date? {
        let key = Key(kind: .pattern(pattern), locale: locale, calendar: calendar, timeZone: timeZone)
        return store.withFormatter(key) { $0.date(from: text) }
    }

    /// Localized skeleton such as `MMMd`; the time zone follows the calendar.
    static func string(from date: Date, template: String, locale: Locale, calendar: Calendar) -> String {
        let key = Key(kind: .template(template), locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return store.withFormatter(key) { $0.string(from: date) }
    }

    /// System date and time styles in the given locale.
    static func string(
        from date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        locale: Locale,
        calendar: Calendar = .current
    ) -> String {
        let key = Key(
            kind: .styles(dateStyle, timeStyle),
            locale: locale,
            calendar: calendar,
            timeZone: calendar.timeZone
        )
        return store.withFormatter(key) { $0.string(from: date) }
    }
}
