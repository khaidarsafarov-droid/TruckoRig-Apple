import Foundation

/// Editable form state for a load, shared by the add and edit screens.
///
/// Kept free of persistence types so validation can be tested directly and so an invalid form
/// never reaches the database.
public struct LoadDraft: Equatable, Sendable {
    public var tripId: String
    public var date: Date
    public var totalRate: Double
    public var totalMiles: Double
    public var stops: [StopDraft]
    public var actualFinishDate: Date?
    public var isDispute: Bool
    public var disputeCompleted: Bool
    public var disputeResponseDate: Date?
    public var disputeAmount: Double?
    public var rawMessage: String?

    public init(
        tripId: String = "",
        date: Date = Date(),
        totalRate: Double = 0,
        totalMiles: Double = 0,
        stops: [StopDraft] = [],
        actualFinishDate: Date? = nil,
        isDispute: Bool = false,
        disputeCompleted: Bool = false,
        disputeResponseDate: Date? = nil,
        disputeAmount: Double? = nil,
        rawMessage: String? = nil
    ) {
        self.tripId = tripId
        self.date = date
        self.totalRate = totalRate
        self.totalMiles = totalMiles
        self.stops = stops
        self.actualFinishDate = actualFinishDate
        self.isDispute = isDispute
        self.disputeCompleted = disputeCompleted
        self.disputeResponseDate = disputeResponseDate
        self.disputeAmount = disputeAmount
        self.rawMessage = rawMessage
    }

    public init(parsed: ParsedLoad, fallbackDate: Date = Date()) {
        self.init(
            tripId: parsed.tripId,
            date: parsed.date ?? fallbackDate,
            totalRate: parsed.totalRate,
            totalMiles: parsed.totalMiles,
            stops: parsed.stops,
            rawMessage: parsed.rawMessage
        )
    }

    // MARK: - Derived

    public var pickups: [StopDraft] { stops.filter { $0.type == .pickup } }
    public var deliveries: [StopDraft] { stops.filter { $0.type == .delivery } }
    public var pointA: String { pickups.first?.cityState ?? "" }
    public var pointB: String { deliveries.last?.cityState ?? "" }
    public var ratePerMile: Double { RPMCalculator.ratePerMile(rate: totalRate, miles: totalMiles) }

    /// Stops renumbered from 1 in their current order.
    public var normalizedStops: [StopDraft] {
        stops.enumerated().map { index, stop in
            var copy = stop
            copy.stopNumber = index + 1
            return copy
        }
    }

    // MARK: - Validation

    public enum ValidationError: Equatable, Sendable {
        case missingTripId
        case nonPositiveRate
        case negativeMiles
        case finishBeforeStart
    }

    public var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []
        if !TripID.isValid(tripId) { errors.append(.missingTripId) }
        if totalRate <= 0 { errors.append(.nonPositiveRate) }
        if totalMiles < 0 { errors.append(.negativeMiles) }
        if let finish = actualFinishDate,
           let start = pickups.compactMap(\.scheduledTime).min(),
           finish < start {
            errors.append(.finishBeforeStart)
        }
        return errors
    }

    public var isValid: Bool { validationErrors.isEmpty }
}
