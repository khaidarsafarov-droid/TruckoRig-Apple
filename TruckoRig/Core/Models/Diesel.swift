import Foundation
import SwiftData

/// One fuel purchase.
@Model
final class Diesel {
    @Attribute(.unique) var id: UUID
    var gallons: Double
    var totalCost: Double
    var pricePerGallon: Double
    var location: String?
    var state: String?
    var date: Date
    var odometer: Int?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        gallons: Double,
        totalCost: Double,
        pricePerGallon: Double = 0,
        location: String? = nil,
        state: String? = nil,
        date: Date = Date(),
        odometer: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.gallons = gallons
        self.totalCost = totalCost
        // Receipts print two of the three numbers as often as all three.
        self.pricePerGallon = pricePerGallon > 0
            ? pricePerGallon
            : (gallons > 0 ? (totalCost / gallons * 1000).rounded() / 1000 : 0)
        self.location = location
        self.state = state
        self.date = date
        self.odometer = odometer
        self.updatedAt = updatedAt
    }
}
