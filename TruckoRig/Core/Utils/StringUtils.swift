import Foundation

/// Number and text formatting shared across screens.
enum Formatters {

    /// The journal is denominated in US dollars regardless of the phone's region: a Russian
    /// interface still tracks American settlements.
    static let currencyCode = "USD"

    /// `$2,500` — whole dollars, for headline figures.
    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    /// `$2,500.50` — cents shown only when they exist.
    static func moneyPrecise(_ value: Double) -> String {
        let hasCents = abs(value.rounded() - value) > 0.004
        return value.formatted(
            .currency(code: currencyCode).precision(.fractionLength(hasCents ? 2 : 0))
        )
    }

    /// `$2.94/mi`.
    static func ratePerMile(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return String(localized: "format.perMile \(value.formatted(.number.precision(.fractionLength(2))))")
    }

    /// `$1,250/day`.
    static func perDay(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return String(localized: "format.perDay \(money(value))")
    }

    /// `850 mi`.
    static func miles(_ value: Double) -> String {
        let rounded = value.formatted(.number.precision(.fractionLength(value < 100 ? 1 : 0)))
        return String(localized: "format.miles \(rounded)")
    }

    /// `6.8 mpg`.
    static func mpg(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return String(localized: "format.mpg \(value.formatted(.number.precision(.fractionLength(1))))")
    }

    static func gallons(_ value: Double) -> String {
        String(localized: "format.gallons \(value.formatted(.number.precision(.fractionLength(1))))")
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var nonEmpty: String? { trimmed.isEmpty ? nil : trimmed }

    /// Case- and diacritic-insensitive contains, for the journal search field.
    func matchesSearch(_ query: String) -> Bool {
        guard !query.trimmed.isEmpty else { return true }
        return range(of: query.trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// `JD` from `John Doe`.
    var initials: String {
        let words = trimmed.split(separator: " ").prefix(2)
        return words.compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}
