import Foundation

/// Best-effort source from fields the journal already stores. No schema change.
public enum LoadSourceTag: String, Equatable, Sendable {
    case relay
    case manual
    case broker

    public static func detect(tripId: String, rawMessage: String?) -> LoadSourceTag {
        let raw = rawMessage ?? ""
        if raw.range(of: "Amazon Relay", options: .caseInsensitive) != nil || raw.contains("PU#") {
            return .relay
        }
        if tripId.hasPrefix("M-") { return .manual }
        let markers = ["Trip ID:", "Total Rate:", "Pu-address:", "Del-address:"]
        let hits = markers.reduce(0) { count, marker in
            raw.range(of: marker, options: .caseInsensitive) != nil ? count + 1 : count
        }
        if hits >= 2 { return .relay }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .manual }
        return .broker
    }
}
