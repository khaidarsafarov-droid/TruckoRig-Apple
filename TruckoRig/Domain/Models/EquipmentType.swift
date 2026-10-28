import Foundation

/// Trailer stored on a load. The raw value is the Android enum name.
public enum EquipmentType: String, CaseIterable, Identifiable, Sendable {
    case dryVan = "DRY_VAN"
    case reefer = "REEFER"
    case flatbed = "FLATBED"
    case powerOnly = "POWER_ONLY"
    case amazonRelay = "AMAZON_RELAY"
    case boxTruck = "BOX_TRUCK"
    case cargoVan = "CARGO_VAN"
    case other = "OTHER"

    public var id: String { rawValue }

    public static func fromStorage(_ raw: String?) -> EquipmentType? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return allCases.first { $0.rawValue.caseInsensitiveCompare(raw.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }
}
