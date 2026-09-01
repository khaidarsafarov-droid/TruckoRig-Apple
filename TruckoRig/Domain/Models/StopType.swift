import Foundation

/// Leg kind of a trip stop. Mirrors `StopType` in the Android app (`PU` / `DEL`).
public enum StopType: String, Codable, CaseIterable, Sendable {
    case pickup = "PU"
    case delivery = "DEL"

    public var shortLabel: String {
        switch self {
        case .pickup: return "PU"
        case .delivery: return "DEL"
        }
    }
}
