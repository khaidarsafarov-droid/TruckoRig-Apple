import Foundation

/// Date formatting for the journal. Formatters are cached: building one per row is a measurable
/// cost in a long list.
enum DateUtils {

    private static let cache = FormatterCache()

    private final class FormatterCache: @unchecked Sendable {
        private var formatters: [String: DateFormatter] = [:]
        private let lock = NSLock()

        func formatter(template: String, locale: Locale) -> DateFormatter {
            stored(key: "template|\(template)|\(locale.identifier)") { formatter in
                formatter.locale = locale
                formatter.setLocalizedDateFormatFromTemplate(template)
            }
        }

        func formatter(format: String, locale: Locale, calendar: Calendar) -> DateFormatter {
            stored(key: Self.cacheKey(
                kind: "format",
                pattern: format,
                locale: locale,
                calendar: calendar
            )) { formatter in
                formatter.locale = locale
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = format
            }
        }

        func formatter(template: String, locale: Locale, calendar: Calendar) -> DateFormatter {
            stored(key: Self.cacheKey(
                kind: "template",
                pattern: template,
                locale: locale,
                calendar: calendar
            )) { formatter in
                formatter.locale = locale
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.setLocalizedDateFormatFromTemplate(template)
            }
        }

        private func stored(key: String, configure: (DateFormatter) -> Void) -> DateFormatter {
            lock.lock()
            defer { lock.unlock() }
            if let existing = formatters[key] { return existing }
            let formatter = DateFormatter()
            configure(formatter)
            formatters[key] = formatter
            return formatter
        }

        private static func cacheKey(kind: String, pattern: String, locale: Locale, calendar: Calendar) -> String {
            let zone = calendar.timeZone.identifier
            return "\(kind)|\(pattern)|\(locale.identifier)|\(calendar.identifier)|\(zone)|\(calendar.firstWeekday)"
        }
    }

    static func string(_ date: Date, template: String, locale: Locale = AppLocale.locale) -> String {
        cache.formatter(template: template, locale: locale).string(from: date)
    }

    /// `dateFormat`, cached per locale and calendar. The home screen asks for this on every body pass.
    static func string(_ date: Date, format: String, locale: Locale, calendar: Calendar) -> String {
        cache.formatter(format: format, locale: locale, calendar: calendar).string(from: date)
    }

    /// Localized template, cached per locale and calendar.
    static func string(_ date: Date, template: String, locale: Locale, calendar: Calendar) -> String {
        cache.formatter(template: template, locale: locale, calendar: calendar).string(from: date)
    }

    /// `Aug 6` — journal rows and week headers.
    static func shortDay(_ date: Date, locale: Locale = AppLocale.locale) -> String {
        string(date, template: "MMMd", locale: locale)
    }

    /// `Wed, Aug 6` — load detail.
    static func weekdayShortDay(_ date: Date, locale: Locale = AppLocale.locale) -> String {
        string(date, template: "EEEMMMd", locale: locale)
    }

    /// `Aug 6, 2025`.
    static func mediumDate(_ date: Date, locale: Locale = AppLocale.locale) -> String {
        string(date, template: "MMMdyyyy", locale: locale)
    }

    /// `Aug 6, 08:00`.
    static func dateTime(_ date: Date, locale: Locale = AppLocale.locale) -> String {
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
