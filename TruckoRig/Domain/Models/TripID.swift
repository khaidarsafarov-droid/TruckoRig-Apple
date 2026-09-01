import Foundation

/// Trip ID handling. The trip ID is the journal's natural key, so normalization has to be
/// identical everywhere a load can enter the app: parser, manual entry, import and cloud sync.
public enum TripID {

    /// Canonical form used for storage and comparison.
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Whether two trip IDs refer to the same trip.
    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalize(lhs) == normalize(rhs)
    }

    private static let relayPattern = Rx(#"^T-[A-Z0-9]{6,}$"#)

    /// `true` for Relay-issued IDs such as `T-116KYL6KW`. Manual IDs are allowed too.
    public static func isRelayFormat(_ raw: String) -> Bool {
        relayPattern.containsMatch(in: normalize(raw))
    }

    public static func isValid(_ raw: String) -> Bool {
        !normalize(raw).isEmpty
    }
}
