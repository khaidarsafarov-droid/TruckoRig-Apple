import Foundation
import Observation

/// A service item: oil change, DOT inspection, tyre rotation.
@Observable
final class MaintenanceTask: Identifiable {
    var id: UUID
    var title: String
    var dueDate: Date?
    /// Odometer reading the service is due at, for mileage-based intervals.
    var dueOdometer: Int?
    var completedDate: Date?
    var cost: Double?
    var notes: String?
    var isArchived: Bool
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        dueOdometer: Int? = nil,
        completedDate: Date? = nil,
        cost: Double? = nil,
        notes: String? = nil,
        isArchived: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.dueOdometer = dueOdometer
        self.completedDate = completedDate
        self.cost = cost
        self.notes = notes
        self.isArchived = isArchived
        self.updatedAt = updatedAt
    }

    var isCompleted: Bool { completedDate != nil }

    func isOverdue(now: Date = Date()) -> Bool {
        guard !isCompleted, let dueDate else { return false }
        return dueDate < now
    }
}
