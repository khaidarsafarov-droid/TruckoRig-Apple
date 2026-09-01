import Foundation

/// Result of parsing one Amazon Relay trip block.
///
/// Deliberately free of persistence types so the parser can be exercised without SwiftData.
public struct ParsedLoad: Equatable, Sendable {
    public var tripId: String
    public var totalRate: Double
    public var totalMiles: Double
    /// Date of the first pickup; `nil` when the message carried no usable schedule.
    public var date: Date?
    public var stops: [StopDraft]
    public var rawMessage: String

    public init(
        tripId: String,
        totalRate: Double,
        totalMiles: Double,
        date: Date?,
        stops: [StopDraft],
        rawMessage: String
    ) {
        self.tripId = tripId
        self.totalRate = totalRate
        self.totalMiles = totalMiles
        self.date = date
        self.stops = stops
        self.rawMessage = rawMessage
    }

    public var pickups: [StopDraft] { stops.filter { $0.type == .pickup } }
    public var deliveries: [StopDraft] { stops.filter { $0.type == .delivery } }

    /// `"City, ST"` of the first pickup.
    public var pointA: String { pickups.first?.cityState ?? "" }
    /// `"City, ST"` of the last delivery.
    public var pointB: String { deliveries.last?.cityState ?? "" }

    public var puCount: Int { pickups.count }
    public var delCount: Int { deliveries.count }
    public var stopCount: Int { stops.count }

    public var firstPickupAt: Date? { pickups.compactMap(\.scheduledTime).min() }
    public var lastDeliveryAt: Date? { deliveries.compactMap(\.scheduledTime).max() }

    public var route: String {
        guard !pointA.isEmpty, !pointB.isEmpty else { return pointA.isEmpty ? pointB : pointA }
        return "\(pointA) → \(pointB)"
    }
}
