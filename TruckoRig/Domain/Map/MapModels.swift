import Foundation

/// Week, month, or year window. Lengths are exact day counts, same as Android `MapPeriod`.
public enum MapPeriod: String, CaseIterable, Sendable, Equatable {
    case week
    case month
    case year

    public var windowMs: Int64 {
        switch self {
        case .week: return 7 * 86_400_000
        case .month: return 30 * 86_400_000
        case .year: return 365 * 86_400_000
        }
    }
}

/// One load reduced to the fields the map is allowed to read.
///
/// Addresses stay only long enough to pull a 2-letter state. Trip id and raw text are not fields,
/// so a report cannot echo them.
public struct MapLoadInput: Equatable, Sendable {
    public var pointA: String
    public var pointB: String
    public var totalRateDollars: Double
    public var totalMiles: Double
    public var deadheadMiles: Double
    public var parsedAtMillis: Int64
    public var updatedAtMillis: Int64
    /// `yyyy-MM-dd`, used only when both timestamps are missing.
    public var filedOnISO: String
    public var equipmentType: String?

    public init(
        pointA: String,
        pointB: String,
        totalRateDollars: Double,
        totalMiles: Double,
        deadheadMiles: Double = 0,
        parsedAtMillis: Int64,
        updatedAtMillis: Int64,
        filedOnISO: String,
        equipmentType: String? = nil
    ) {
        self.pointA = pointA
        self.pointB = pointB
        self.totalRateDollars = totalRateDollars
        self.totalMiles = totalMiles
        self.deadheadMiles = deadheadMiles
        self.parsedAtMillis = parsedAtMillis
        self.updatedAtMillis = updatedAtMillis
        self.filedOnISO = filedOnISO
        self.equipmentType = equipmentType
    }

    /// Loaded miles plus deadhead. Android `Load.drivenMiles`.
    public var drivenMiles: Double {
        totalMiles + max(0, deadheadMiles)
    }
}

public enum CrowdRateSource: String, Equatable, Sendable {
    case me
    case friend
    case network
}

/// On-device lane row. `rate` is RPM × miles for coloring, not a value that leaves the phone.
public struct CrowdRateReport: Equatable, Sendable {
    public var id: String
    public var fromState: String
    public var toState: String
    public var rpm: MapMoney
    public var rate: MapMoney
    public var miles: Double
    public var reportedAtMillis: Int64
    public var source: CrowdRateSource
    public var equipmentType: String?

    public init(
        id: String,
        fromState: String,
        toState: String,
        rpm: MapMoney,
        rate: MapMoney,
        miles: Double,
        reportedAtMillis: Int64,
        source: CrowdRateSource,
        equipmentType: String? = nil
    ) {
        self.id = id
        self.fromState = fromState
        self.toState = toState
        self.rpm = rpm
        self.rate = rate
        self.miles = miles
        self.reportedAtMillis = reportedAtMillis
        self.source = source
        self.equipmentType = equipmentType
    }
}

public struct CrowdLaneAggregate: Equatable, Sendable {
    public var fromState: String
    public var toState: String
    public var tripCount: Int
    public var avgRpm: MapMoney
    public var totalRevenue: MapMoney
    public var totalMiles: Double
}

public struct CrowdStateSummary: Equatable, Sendable {
    public var stateCode: String
    public var outboundTrips: Int
    public var avgOutboundRpm: MapMoney
    public var totalRevenue: MapMoney
    public var totalMiles: Double
    public var recent: [CrowdRateReport]
}

public struct AnonymizedRpmSample: Equatable, Sendable {
    public var rpm: Double
    public var miles: Double
    public var region: String?
    public var weekNumber: Int
    public var fromState: String
    public var toState: String
    public var week: Int
    public var year: Int
    public var equipmentType: String?
}

public enum USHeatLevel: String, Equatable, Sendable {
    case high
    case medium
    case low
}

public enum StateRating: String, Equatable, Sendable {
    case good
    case bad
    case neutral
    case noData
}

public struct USStateMetric: Equatable, Sendable, Identifiable {
    public var code: String
    public var revenue: Double
    public var trips: Int
    public var level: USHeatLevel
    public var revenuePerMile: Double
    public var avgMilesPerTrip: Double
    public var rating: StateRating

    public var id: String { code }
}

/// Insertion order matches Android `getUsStateCodes`, including DC and Puerto Rico.
public enum USStateCodes {
    public static let all: [String] = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI",
        "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN",
        "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH",
        "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA",
        "WV", "WI", "WY", "PR",
    ]

    public static let known: Set<String> = Set(all)
}

/// Persisted map selection. A blank stored value opens on Kentucky, as Android does.
public enum MapSelection {
    public static let storageKey = "selected_stats_state"
    public static let defaultCode = "KY"

    public static func resolved(_ stored: String?) -> String {
        let trimmed = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultCode : trimmed
    }
}

/// Continental US framing used by both the card and the fullscreen map.
public enum MapCamera {
    public static let latitude = 39.5
    public static let longitude = -98.35
    public static let cardZoom: Float = 4
    public static let fullscreenZoom: Float = 3.5
}

/// Age label bucket for a recent outbound rate. The UI localizes the words.
public enum CrowdAge: Equatable, Sendable {
    case minutes(Int)
    case hours(Int)
    case days(Int)

    public static func classify(ageMs: Int64) -> CrowdAge {
        let age = max(0, ageMs)
        let hours = age / 3_600_000
        if hours < 1 {
            return .minutes(Int(max(1, age / 60_000)))
        }
        if hours < 24 {
            return .hours(Int(hours))
        }
        return .days(Int(max(1, age / 86_400_000)))
    }
}

public struct MapSnapshot: Equatable, Sendable {
    public var metrics: [USStateMetric]
    public var selectedCode: String
    public var period: MapPeriod
    public var tripCount: Int
    public var stateSummary: CrowdStateSummary?
    public var topLanes: [CrowdLaneAggregate]

    public static let empty = MapSnapshot(
        metrics: [],
        selectedCode: "",
        period: .week,
        tripCount: 0,
        stateSummary: nil,
        topLanes: []
    )
}
