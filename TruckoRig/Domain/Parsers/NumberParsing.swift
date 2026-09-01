import Foundation

/// Money and mileage parsing for pasted load text.
public enum NumberParsing {

    /// Parses `2500`, `$2,500.00`, `2500,50` (EU decimal comma) and `2710.550048828125`.
    ///
    /// A bare comma is only treated as a thousands separator when the tail is not a 1–2 digit
    /// fraction, otherwise `2500,50` would come back as 250050.
    public static func parseMoney(_ raw: String?) -> Double {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return 0 }
        text = text.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard !text.isEmpty else { return 0 }

        let hasDot = text.contains(".")
        let hasComma = text.contains(",")
        if hasDot && hasComma {
            // Whichever separator comes last is the decimal one.
            if let lastDot = text.lastIndex(of: "."), let lastComma = text.lastIndex(of: ",") {
                if lastComma > lastDot {
                    text = text.replacingOccurrences(of: ".", with: "")
                    text = text.replacingOccurrences(of: ",", with: ".")
                } else {
                    text = text.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if hasComma {
            let fraction = text.split(separator: ",").last.map(String.init) ?? ""
            let isDecimalComma = text.filter { $0 == "," }.count == 1 && (1...2).contains(fraction.count)
            text = isDecimalComma
                ? text.replacingOccurrences(of: ",", with: ".")
                : text.replacingOccurrences(of: ",", with: "")
        }

        return Double(text) ?? 0
    }

    public static func parseMiles(_ raw: String?) -> Double {
        guard let raw else { return 0 }
        let cleaned = raw
            .replacingOccurrences(of: "mi", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned) ?? 0
    }

    private static let absurdMilesThreshold: Double = 10_000
    private static let minPlausibleRPMBeforeFix: Double = 0.5
    private static let plausibleRPMAfterFix: ClosedRange<Double> = 0.8...6.0
    private static let fixedMilesRange: ClosedRange<Double> = 50...5_000
    private static let decimalFixDivisors: [Double] = [100, 10, 1000]

    /// Repairs Relay exports that dropped the decimal point from Total Loaded Miles
    /// (`182781` instead of `1827.81`), which otherwise drags fleet RPM down to ~$1.
    ///
    /// Only rewrites values that are absurd on their face and only when the correction lands in a
    /// plausible RPM band, so legitimate long hauls are left alone.
    public static func sanitizeLoadedMiles(_ miles: Double, totalRate: Double) -> Double {
        guard miles >= absurdMilesThreshold, totalRate > 0 else { return miles }
        guard totalRate / miles < minPlausibleRPMBeforeFix else { return miles }
        for divisor in decimalFixDivisors {
            let fixed = miles / divisor
            guard fixedMilesRange.contains(fixed) else { continue }
            if plausibleRPMAfterFix.contains(totalRate / fixed) {
                return (fixed * 100).rounded() / 100
            }
        }
        return miles
    }
}
