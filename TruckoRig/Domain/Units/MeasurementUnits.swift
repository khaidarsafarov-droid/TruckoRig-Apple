import Foundation

/// Distance and volume the driver sees. Stored journal values stay miles and US gallons.
public enum MeasurementSystem: String, Codable, Equatable, Sendable, CaseIterable {
    case miles
    case kilometers
}

/// Exact factors shared by the app, the widget and the accountant workbook.
///
/// 1 mile = 1.609344 kilometers. 1 US gallon = 3.785411784 liters.
/// Fuel economy flips: miles per gallon becomes liters per 100 kilometers.
public enum MeasurementUnits {
    public static let kilometersPerMile: Double = 1.609344
    public static let litersPerUSGallon: Double = 3.785411784

    public static func kilometers(fromMiles miles: Double) -> Double {
        miles * kilometersPerMile
    }

    public static func miles(fromKilometers kilometers: Double) -> Double {
        kilometers / kilometersPerMile
    }

    public static func liters(fromGallons gallons: Double) -> Double {
        gallons * litersPerUSGallon
    }

    public static func gallons(fromLiters liters: Double) -> Double {
        liters / litersPerUSGallon
    }

    /// US miles/gallon → L/100 km. Zero when the rate is missing or not positive.
    public static func litersPer100Kilometers(fromMilesPerGallon mpg: Double) -> Double {
        guard mpg > 0, mpg.isFinite else { return 0 }
        return (litersPerUSGallon * 100) / (mpg * kilometersPerMile)
    }

    /// L/100 km → US miles/gallon. Zero when the rate is missing or not positive.
    public static func milesPerGallon(fromLitersPer100Kilometers litersPer100km: Double) -> Double {
        guard litersPer100km > 0, litersPer100km.isFinite else { return 0 }
        return (litersPerUSGallon * 100) / (litersPer100km * kilometersPerMile)
    }

    public static func pricePerLiter(fromPricePerGallon price: Double) -> Double {
        price / litersPerUSGallon
    }

    public static func pricePerGallon(fromPricePerLiter price: Double) -> Double {
        price * litersPerUSGallon
    }

    /// Dollars per mile → dollars per kilometer.
    public static func perKilometer(fromPerMile value: Double) -> Double {
        value / kilometersPerMile
    }

    /// Dollars per kilometer → dollars per mile.
    public static func perMile(fromPerKilometer value: Double) -> Double {
        value * kilometersPerMile
    }

    public static func displayDistance(_ miles: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? kilometers(fromMiles: miles) : miles
    }

    public static func storageDistance(_ display: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? miles(fromKilometers: display) : display
    }

    public static func displayVolume(_ gallons: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? liters(fromGallons: gallons) : gallons
    }

    public static func storageVolume(_ display: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? gallons(fromLiters: display) : display
    }

    public static func displayUnitPrice(_ perGallon: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? pricePerLiter(fromPricePerGallon: perGallon) : perGallon
    }

    public static func storageUnitPrice(_ display: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? pricePerGallon(fromPricePerLiter: display) : display
    }

    public static func displayPerDistance(_ perMile: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? perKilometer(fromPerMile: perMile) : perMile
    }

    public static func storagePerDistance(_ display: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? perMile(fromPerKilometer: display) : display
    }

    /// Stored economy is miles per gallon. Kilometers show liters per 100 km.
    public static func displayEconomy(_ milesPerGallon: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? litersPer100Kilometers(fromMilesPerGallon: milesPerGallon) : milesPerGallon
    }

    public static func storageEconomy(_ display: Double, system: MeasurementSystem) -> Double {
        system == .kilometers ? milesPerGallon(fromLitersPer100Kilometers: display) : display
    }
}

/// How the mile/kilometer choice is remembered.
///
/// An absent explicit value follows the language: French uses kilometers, every other language
/// stays on miles. A saved choice always wins, including after a language change.
public enum UnitPreference {
    /// Explicit driver choice inside the App Group. Absent until the driver taps the switch.
    public static let explicitKey = "truckorig.unit.explicit"
    /// Resolved system the widget paints. The app rewrites it; it is not itself a choice.
    public static let resolvedKey = "truckorig.widget.measurementSystem"

    public static func resolve(explicit: MeasurementSystem?, languageCode: String?) -> MeasurementSystem {
        if let explicit { return explicit }
        return followsFrench(languageCode) ? .kilometers : .miles
    }

    /// `fr`, `fr-CA` and `fr_CA` follow kilometers. `en`, `ru`, `es` and anything else stay miles.
    public static func followsFrench(_ languageCode: String?) -> Bool {
        let code = (languageCode ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        return code == "fr" || code.hasPrefix("fr-")
    }

    /// App language raw value (`french`, `english`, `russian`, `system`) plus the device list.
    public static func languageCode(appLanguageRaw: String, preferredLanguages: [String]) -> String {
        switch appLanguageRaw {
        case "french": return "fr"
        case "english": return "en"
        case "russian": return "ru"
        default:
            return preferredLanguages.first ?? "en"
        }
    }

    public static func readResolved(_ defaults: UserDefaults?) -> MeasurementSystem {
        guard let raw = defaults?.string(forKey: resolvedKey),
              let system = MeasurementSystem(rawValue: raw) else {
            return .miles
        }
        return system
    }
}

/// App Group (or any `UserDefaults` suite) backing the explicit choice.
public struct UnitPreferenceStore {
    public let defaults: UserDefaults
    public let explicitKey: String

    public init(defaults: UserDefaults, explicitKey: String = UnitPreference.explicitKey) {
        self.defaults = defaults
        self.explicitKey = explicitKey
    }

    public var explicit: MeasurementSystem? {
        guard let raw = defaults.string(forKey: explicitKey) else { return nil }
        return MeasurementSystem(rawValue: raw)
    }

    public func setExplicit(_ system: MeasurementSystem) {
        defaults.set(system.rawValue, forKey: explicitKey)
    }

    public func resolve(languageCode: String?) -> MeasurementSystem {
        UnitPreference.resolve(explicit: explicit, languageCode: languageCode)
    }

    public func publishResolved(_ system: MeasurementSystem) {
        defaults.set(system.rawValue, forKey: UnitPreference.resolvedKey)
    }
}
