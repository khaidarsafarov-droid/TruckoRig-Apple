import Foundation

/// Flattened view of a load used by the goal, yield and analytics calculators.
///
/// SwiftData models project into this so the math stays pure and unit-testable.
public struct LoadSummary: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var tripId: String
    public var totalRate: Double
    public var totalMiles: Double
    public var firstPickupAt: Date?
    public var lastDeliveryAt: Date?
    /// Driver override for when the load actually ended.
    public var actualFinishAt: Date?
    /// Persisted duration, used when stops are not hydrated.
    public var storedDurationDays: Double
    public var penaltiesTotal: Double
    public var isDispute: Bool
    public var disputeCompleted: Bool
    public var originState: String
    public var destinationState: String

    public init(
        id: UUID = UUID(),
        tripId: String = "",
        totalRate: Double = 0,
        totalMiles: Double = 0,
        firstPickupAt: Date? = nil,
        lastDeliveryAt: Date? = nil,
        actualFinishAt: Date? = nil,
        storedDurationDays: Double = 0,
        penaltiesTotal: Double = 0,
        isDispute: Bool = false,
        disputeCompleted: Bool = false,
        originState: String = "",
        destinationState: String = ""
    ) {
        self.id = id
        self.tripId = tripId
        self.totalRate = totalRate
        self.totalMiles = totalMiles
        self.firstPickupAt = firstPickupAt
        self.lastDeliveryAt = lastDeliveryAt
        self.actualFinishAt = actualFinishAt
        self.storedDurationDays = storedDurationDays
        self.penaltiesTotal = penaltiesTotal
        self.isDispute = isDispute
        self.disputeCompleted = disputeCompleted
        self.originState = originState
        self.destinationState = destinationState
    }

    public var isActiveDispute: Bool { isDispute && !disputeCompleted }
    /// Gross after penalties, never negative.
    public var netRate: Double { max(0, totalRate - penaltiesTotal) }
}

/// Aggregate of a set of loads (a week, a month, a filter result).
public struct LoadTotals: Equatable, Sendable {
    public var loadCount: Int
    public var totalRate: Double
    public var totalMiles: Double
    public var penalties: Double

    public init(loadCount: Int = 0, totalRate: Double = 0, totalMiles: Double = 0, penalties: Double = 0) {
        self.loadCount = loadCount
        self.totalRate = totalRate
        self.totalMiles = totalMiles
        self.penalties = penalties
    }

    public var netRate: Double { max(0, totalRate - penalties) }
    public var ratePerMile: Double { RPMCalculator.ratePerMile(rate: totalRate, miles: totalMiles) }

    public static func of(_ loads: [LoadSummary]) -> LoadTotals {
        LoadTotals(
            loadCount: loads.count,
            totalRate: loads.reduce(0) { $0 + $1.totalRate },
            totalMiles: loads.reduce(0) { $0 + $1.totalMiles },
            penalties: loads.reduce(0) { $0 + $1.penaltiesTotal }
        )
    }
}
