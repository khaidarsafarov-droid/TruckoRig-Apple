import Foundation
import SwiftData

/// A settlement payment received from the carrier.
@Model
final class Paycheck {
    @Attribute(.unique) var id: UUID
    var amount: Double
    var date: Date
    var company: String?
    var notes: String?
    var weekNumber: Int
    var year: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        amount: Double,
        date: Date = Date(),
        company: String? = nil,
        notes: String? = nil,
        weekNumber: Int = 0,
        year: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.company = company
        self.notes = notes
        self.weekNumber = weekNumber
        self.year = year
        self.updatedAt = updatedAt
    }

    func refreshWeek(week: TruckingWeek = TruckingWeek()) {
        let ref = week.week(for: date)
        weekNumber = ref.weekNumber
        year = ref.year
    }
}
