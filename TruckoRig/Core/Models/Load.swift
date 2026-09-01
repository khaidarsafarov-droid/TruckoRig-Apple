import Foundation
import SwiftData

/// One trip in the driver's journal. The trip ID is the natural key: Relay reposts the same trip
/// many times, and re-importing must update the row rather than create a second one.
@Model
final class Load {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var tripId: String

    /// Day the load is filed under — the first pickup, anchored at local noon.
    var date: Date
    var totalRate: Double
    var totalMiles: Double
    /// `"City, ST"` of the first pickup.
    var pointA: String?
    /// `"City, ST"` of the last delivery.
    var pointB: String?
    var puCount: Int
    var delCount: Int
    var stopCount: Int
    /// Reporting week the load settles in.
    var weekNumber: Int
    var year: Int
    var rawMessage: String?

    /// Set once when the load is first created and never touched again, so the journal can always
    /// tell when a trip entered the system regardless of later edits.
    var parsedAt: Date
    var updatedAt: Date

    var isDispute: Bool
    var disputeCompleted: Bool
    var disputeResponseDate: Date?
    var disputeAmount: Double?

    /// Driver override for when the load actually ended, used instead of the last delivery.
    var actualFinishDate: Date?
    /// Cached first pickup / last delivery instants so list queries do not have to load stops.
    var firstPickupAt: Date?
    var lastDeliveryAt: Date?
    /// Cached PU→DEL duration in days, for rows fetched without their stops.
    var durationDays: Double

    @Relationship(deleteRule: .cascade, inverse: \Stop.load) var stops: [Stop]?
    @Relationship(deleteRule: .cascade, inverse: \Penalty.load) var penalties: [Penalty]?
    @Relationship(deleteRule: .nullify, inverse: \Photo.load) var photos: [Photo]?
    @Relationship(deleteRule: .nullify, inverse: \Scan.load) var scans: [Scan]?

    init(
        id: UUID = UUID(),
        tripId: String,
        date: Date,
        totalRate: Double = 0,
        totalMiles: Double = 0,
        pointA: String? = nil,
        pointB: String? = nil,
        puCount: Int = 0,
        delCount: Int = 0,
        stopCount: Int = 0,
        weekNumber: Int = 0,
        year: Int = 0,
        rawMessage: String? = nil,
        parsedAt: Date = Date(),
        updatedAt: Date = Date(),
        isDispute: Bool = false,
        disputeCompleted: Bool = false,
        disputeResponseDate: Date? = nil,
        disputeAmount: Double? = nil,
        actualFinishDate: Date? = nil,
        firstPickupAt: Date? = nil,
        lastDeliveryAt: Date? = nil,
        durationDays: Double = 0
    ) {
        self.id = id
        self.tripId = TripID.normalize(tripId)
        self.date = date
        self.totalRate = totalRate
        self.totalMiles = totalMiles
        self.pointA = pointA
        self.pointB = pointB
        self.puCount = puCount
        self.delCount = delCount
        self.stopCount = stopCount
        self.weekNumber = weekNumber
        self.year = year
        self.rawMessage = rawMessage
        self.parsedAt = parsedAt
        self.updatedAt = updatedAt
        self.isDispute = isDispute
        self.disputeCompleted = disputeCompleted
        self.disputeResponseDate = disputeResponseDate
        self.disputeAmount = disputeAmount
        self.actualFinishDate = actualFinishDate
        self.firstPickupAt = firstPickupAt
        self.lastDeliveryAt = lastDeliveryAt
        self.durationDays = durationDays
    }
}
