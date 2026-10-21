import Foundation
import Observation

/// A settlement payment received from the carrier.
@Observable
final class Paycheck: Identifiable {
    var id: UUID
    var amount: Double
    var date: Date
    var company: String?
    var notes: String?
    var weekNumber: Int
    var year: Int
    /// Settlement gross when the statement prints one. `amount` is the net the driver takes home.
    var grossAmount: Double?
    var driverName: String?
    var rawText: String?
    var sourceFileName: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        amount: Double,
        date: Date = Date(),
        company: String? = nil,
        notes: String? = nil,
        weekNumber: Int = 0,
        year: Int = 0,
        grossAmount: Double? = nil,
        driverName: String? = nil,
        rawText: String? = nil,
        sourceFileName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.company = company
        self.notes = notes
        self.weekNumber = weekNumber
        self.year = year
        self.grossAmount = grossAmount
        self.driverName = driverName
        self.rawText = rawText
        self.sourceFileName = sourceFileName
        self.updatedAt = updatedAt
    }

    func refreshWeek(week: TruckingWeek = TruckingWeek()) {
        let ref = week.week(for: date)
        weekNumber = ref.weekNumber
        year = ref.year
    }
}
