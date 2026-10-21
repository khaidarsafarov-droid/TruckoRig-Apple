import Foundation
import Observation

/// A deduction against a load: late fee, lumper, damage claim.
@Observable
final class Penalty: Identifiable {
    var id: UUID
    var summary: String
    var amount: Double
    var date: Date

    var load: Load?

    init(
        id: UUID = UUID(),
        summary: String,
        amount: Double,
        date: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.amount = amount
        self.date = date
    }
}
