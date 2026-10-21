import Foundation
import Observation

/// One fuel purchase.
@Observable
final class Diesel: Identifiable {
    var id: UUID
    var gallons: Double
    var totalCost: Double
    var pricePerGallon: Double
    var location: String?
    var state: String?
    var date: Date
    var odometer: Int?
    /// Pump price before the fleet discount. `pricePerGallon` stays the price used when only one is known.
    var discountPricePerGallon: Double?
    var rawText: String?
    var receiptFileName: String?
    /// Spreadsheet or photo the fill was imported from. Rows that share a file share a reporting week.
    var sourceFileName: String?
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
        discountPricePerGallon: Double? = nil,
        rawText: String? = nil,
        receiptFileName: String? = nil,
        sourceFileName: String? = nil,
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
        self.discountPricePerGallon = discountPricePerGallon
        self.rawText = rawText
        self.receiptFileName = receiptFileName
        self.sourceFileName = sourceFileName
        self.updatedAt = updatedAt
    }
}
