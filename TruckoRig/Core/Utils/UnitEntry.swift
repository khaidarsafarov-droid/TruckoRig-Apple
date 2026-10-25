import SwiftUI

/// Keeps a stored mile or gallon value while the field shows the driver's unit.
///
/// The number field writes the parsed text on appear. When that text is only the rounded
/// display of the stored value, the stored miles or gallons stay untouched.
enum UnitEntry {
    static func binding(
        stored: Binding<Double>,
        toDisplay: @escaping (Double) -> Double,
        toStorage: @escaping (Double) -> Double
    ) -> Binding<Double> {
        Binding(
            get: { toDisplay(stored.wrappedValue) },
            set: { proposed in
                let current = toDisplay(stored.wrappedValue)
                if fieldText(current) == fieldText(proposed) { return }
                stored.wrappedValue = toStorage(proposed)
            }
        )
    }

    static func distance(
        stored: Binding<Double>,
        system: MeasurementSystem
    ) -> Binding<Double> {
        binding(
            stored: stored,
            toDisplay: { MeasurementUnits.displayDistance($0, system: system) },
            toStorage: { MeasurementUnits.storageDistance($0, system: system) }
        )
    }

    static func volume(
        stored: Binding<Double>,
        system: MeasurementSystem
    ) -> Binding<Double> {
        binding(
            stored: stored,
            toDisplay: { MeasurementUnits.displayVolume($0, system: system) },
            toStorage: { MeasurementUnits.storageVolume($0, system: system) }
        )
    }

    static func unitPrice(
        stored: Binding<Double>,
        system: MeasurementSystem
    ) -> Binding<Double> {
        binding(
            stored: stored,
            toDisplay: { MeasurementUnits.displayUnitPrice($0, system: system) },
            toStorage: { MeasurementUnits.storageUnitPrice($0, system: system) }
        )
    }

    static func perDistance(
        stored: Binding<Double>,
        system: MeasurementSystem
    ) -> Binding<Double> {
        binding(
            stored: stored,
            toDisplay: { MeasurementUnits.displayPerDistance($0, system: system) },
            toStorage: { MeasurementUnits.storagePerDistance($0, system: system) }
        )
    }

    /// Turns a typed distance into stored miles. An unchanged reading of `originalMiles` is kept.
    static func commitDistance(text: String, originalMiles: Double?, system: MeasurementSystem) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entered = DecimalInput.parse(trimmed) else { return nil }
        if let originalMiles {
            let shown = MeasurementUnits.displayDistance(originalMiles, system: system)
            if fieldText(shown) == fieldText(entered) { return originalMiles }
            if Int(shown.rounded()) == Int(entered.rounded()), trimmed.allSatisfy({ $0.isNumber }) {
                return originalMiles
            }
        }
        return MeasurementUnits.storageDistance(entered, system: system)
    }

    static func storageDistanceText(_ text: String, system: MeasurementSystem) -> String {
        guard let stored = commitDistance(text: text, originalMiles: nil, system: system) else { return text }
        return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), stored)
    }

    /// Same rounding the numeric field uses, so a display-only rewrite does not move storage.
    static func fieldText(_ value: Double) -> String {
        abs(value.rounded() - value) > 0.004
            ? String(format: "%.2f", value)
            : String(format: "%.0f", value)
    }
}
