import Foundation

/// Number and text formatting shared across screens.
enum Formatters {

    /// The journal is denominated in US dollars regardless of the phone's region: a Russian
    /// interface still tracks American settlements.
    static let currencyCode = "USD"

    /// Dollars stay in US grouping. Weekday names and mile counts follow `AppLocale`.
    private static var dollarLocale: Locale { Locale(identifier: "en_US") }

    /// `$2,500` — whole dollars, for headline figures.
    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).precision(.fractionLength(0)).locale(dollarLocale))
    }

    /// `$2,500.50` — cents shown only when they exist.
    static func moneyPrecise(_ value: Double) -> String {
        let hasCents = abs(value.rounded() - value) > 0.004
        return value.formatted(
            .currency(code: currencyCode).precision(.fractionLength(hasCents ? 2 : 0)).locale(dollarLocale)
        )
    }

    /// `$2.94/mi`, or `$1.83/km` when the driver is looking at kilometers.
    static func ratePerMile(_ value: Double, system: MeasurementSystem = .miles) -> String {
        guard value > 0 else { return "—" }
        let shown = MeasurementUnits.displayPerDistance(value, system: system)
        let text = shown.formatted(.number.precision(.fractionLength(2)).locale(AppLocale.locale))
        if system == .kilometers {
            return String(localized: "format.perKilometer \(text)")
        }
        return String(localized: "format.perMile \(text)")
    }

    /// `$1,250/day`.
    static func perDay(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        return String(localized: "format.perDay \(money(value))")
    }

    /// `850 mi` or `1,368 km`. `value` is stored miles.
    static func miles(_ value: Double, system: MeasurementSystem = .miles) -> String {
        let shown = MeasurementUnits.displayDistance(value, system: system)
        let rounded = shown.formatted(.number.precision(.fractionLength(shown < 100 ? 1 : 0)).locale(AppLocale.locale))
        if system == .kilometers {
            return String(localized: "format.kilometers \(rounded)")
        }
        return String(localized: "format.miles \(rounded)")
    }

    /// `6.8 mpg`, or liters per 100 km when `system` is kilometers. `value` is miles per gallon.
    static func mpg(_ value: Double, system: MeasurementSystem = .miles) -> String {
        guard value > 0 else { return "—" }
        if system == .kilometers {
            let shown = MeasurementUnits.displayEconomy(value, system: system)
            guard shown > 0 else { return "—" }
            return String(localized: "format.lPer100km \(shown.formatted(.number.precision(.fractionLength(1)).locale(AppLocale.locale)))")
        }
        return String(localized: "format.mpg \(value.formatted(.number.precision(.fractionLength(1)).locale(AppLocale.locale)))")
    }

    /// `40.0 gal` or `151.4 L`. `value` is stored US gallons.
    static func gallons(_ value: Double, system: MeasurementSystem = .miles) -> String {
        let shown = MeasurementUnits.displayVolume(value, system: system)
        let text = shown.formatted(.number.precision(.fractionLength(1)).locale(AppLocale.locale))
        if system == .kilometers {
            return String(localized: "format.liters \(text)")
        }
        return String(localized: "format.gallons \(text)")
    }

    /// `$3.500` per gallon, or per liter when `system` is kilometers.
    static func unitPrice(_ perGallon: Double, system: MeasurementSystem = .miles) -> String {
        let shown = MeasurementUnits.displayUnitPrice(perGallon, system: system)
        return shown.formatted(.currency(code: currencyCode).precision(.fractionLength(3)).locale(dollarLocale))
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)).locale(AppLocale.locale))
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
