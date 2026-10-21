import Foundation

/// Date strings pulled off receipts and settlements.
///
/// Ports the Android `ParseUtils.normalizeDate` / `normalizeTextMonthDate` paths that receipts use.
/// A missing year uses `defaultYear` (the load parser still owns Relay's year repair).
public enum ReceiptDateParser {

    public static func normalize(_ raw: String?, defaultYear: Int = Calendar.current.component(.year, from: Date())) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return "" }
        if let iso = Rx(#"(\d{4})-(\d{2})-(\d{2})"#, options: []).firstMatch(in: trimmed)?.groupOrEmpty(0), iso.count == 10 {
            return iso
        }
        if let european = Rx(#"(\d{2})\.(\d{2})\.(\d{4})"#, options: []).firstMatch(in: trimmed),
           let day = european.group(1), let month = european.group(2), let year = european.group(3) {
            return "\(year)-\(month)-\(day)"
        }
        if let dashed = Rx(#"(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})"#, options: []).firstMatch(in: trimmed),
           let first = Int(dashed.groupOrEmpty(1)),
           let second = Int(dashed.groupOrEmpty(2)) {
            let year = year(from: dashed.groupOrEmpty(3), defaultYear: defaultYear)
            let month: Int
            let day: Int
            if first > 12 && (1...12).contains(second) {
                month = second
                day = first
            } else if second > 12 && (1...12).contains(first) {
                month = first
                day = second
            } else {
                month = first
                day = second
            }
            guard (1...12).contains(month), (1...31).contains(day) else { return textMonth(trimmed, defaultYear: defaultYear) }
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
        if let us = Rx(#"(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?"#, options: []).firstMatch(in: trimmed),
           let month = Int(us.groupOrEmpty(1)),
           let day = Int(us.groupOrEmpty(2)),
           (1...12).contains(month), (1...31).contains(day) {
            let year = year(from: us.group(3) ?? "", defaultYear: defaultYear)
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
        return textMonth(trimmed, defaultYear: defaultYear)
    }

    public static func textMonth(_ raw: String, defaultYear: Int) -> String {
        let months = [
            "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
            "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
            "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10, "nov": 11, "november": 11, "dec": 12, "december": 12,
        ]
        let pattern = #"(?i)\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+(\d{1,2})(?:,)?\s+(\d{2,4})\b"#
        if let match = Rx(pattern, options: []).firstMatch(in: raw),
           let month = months[match.groupOrEmpty(1).lowercased()],
           let day = Int(match.groupOrEmpty(2)), (1...31).contains(day) {
            return String(format: "%04d-%02d-%02d", year(from: match.groupOrEmpty(3), defaultYear: defaultYear), month, day)
        }
        let dayFirst = #"(?i)\b(\d{1,2})\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?,?\s+(\d{2,4})\b"#
        if let match = Rx(dayFirst, options: []).firstMatch(in: raw),
           let day = Int(match.groupOrEmpty(1)), (1...31).contains(day),
           let month = months[match.groupOrEmpty(2).lowercased()] {
            return String(format: "%04d-%02d-%02d", year(from: match.groupOrEmpty(3), defaultYear: defaultYear), month, day)
        }
        return ""
    }

    private static func year(from raw: String, defaultYear: Int) -> Int {
        switch raw.count {
        case 4: return Int(raw) ?? defaultYear
        case 2: return 2000 + (Int(raw) ?? (defaultYear % 100))
        default: return defaultYear
        }
    }
}
