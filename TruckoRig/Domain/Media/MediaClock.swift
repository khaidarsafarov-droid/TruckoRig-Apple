import Foundation

/// Date patterns copied from Android `SimpleDateFormat` / `DateTimeFormatter`.
///
/// File names use `Locale.US`. The watermark clock uses the device locale on Android
/// (`Locale.getDefault()`); callers pass that locale in.
public enum MediaClock {

    public static func format(
        _ date: Date,
        pattern: String,
        timeZone: TimeZone,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        formatter.calendar = calendar
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    public static func epochMillis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    public static func date(fromEpochMillis millis: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }
}
