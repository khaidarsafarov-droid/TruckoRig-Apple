import Foundation
import Observation

/// A driver expense that is not diesel, a paycheck or a load penalty.
///
/// Parking, scales and wash receipts live here. The photo is a file the driver can send to the
/// company; Android does not run OCR on these.
@Observable
final class MiscExpense: Identifiable {
    var id: UUID
    var amount: Double
    var expenseDescription: String
    var date: Date
    var receiptFileName: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        amount: Double,
        expenseDescription: String,
        date: Date = Date(),
        receiptFileName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.expenseDescription = expenseDescription
        self.date = date
        self.receiptFileName = receiptFileName
        self.updatedAt = updatedAt
    }
}

/// One manual per-diem day. `included` forces the day on; otherwise the day is forced off.
struct PerDiemOverride: Identifiable, Equatable {
    var isoDate: String
    var included: Bool

    var id: String { isoDate }
}
