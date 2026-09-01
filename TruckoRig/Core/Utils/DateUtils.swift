import Foundation

/// Date formatting for the journal. Formatters are cached: building one per row is a measurable
/// cost in a long list.
enum DateUtils {

    private static let cache = FormatterCache()

    private final class FormatterCache: @unchecked Sendable {
        private var formatters: [String: DateFormatter] = [:]
        private let lock = NSLock()

        func formatter(template: String, locale: Locale) -> DateFormatter {
            let key = "\(template)|\(locale.identifier)"
            lock.lock()
            defer { lock.unlock() }
            if let existing = formatters[key] { return existing }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            formatters[key] = formatter
            return formatter
        }
    }

    static func string(_ date: Date, template: String, locale: Locale = .current) -> String {
        cache.formatter(template: template, locale: locale).string(from: date)
    }

    /// `Aug 6` — journal rows and week headers.
    static func shortDay(_ date: Date, locale: Locale = .current) -> String {
        string(date, template: "MMMd", locale: locale)
    }

    /// `Wed, Aug 6` — load detail.
    static func weekdayShortDay(_ date: Date, locale: Locale = .current) -> String {
        string(date, template: "EEEMMMd", locale: locale)
    }

    /// `Aug 6, 2025`.
    static func mediumDate(_ date: Date, locale: Locale = .current) -> String {
        string(date, template: "MMMdyyyy", locale: locale)
    }

    /// `Aug 6, 08:00`.
    static func dateTime(_ date: Date, locale: Locale = .current) -> String {
        string(date, template: "MMMdjm", locale: locale)
    }

    /// `2025-08-06`, for exports and file names.
    static func isoDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `2 days` / `1 day`, for load durations.
    static func durationDays(_ days: Double) -> String {
        let whole = max(1, Int(days.rounded(.up)))
        return String(localized: "duration.days \(whole)")
    }
}
