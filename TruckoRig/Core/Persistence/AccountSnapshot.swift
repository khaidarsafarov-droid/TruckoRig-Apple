import Foundation

/// Whole-account payload for JSON backup and restore.
///
/// Conflicts resolve last-write-wins on `updatedAt` per row. The on-disk shape stays compatible
/// with files previously exported from this app.
struct AccountSnapshot: Codable, Equatable {
    var schemaVersion: Int = 1
    var updatedAt: Date
    var loads: [LoadDTO]
    var paychecks: [PaycheckDTO]
    var diesel: [DieselDTO]
    var maintenance: [MaintenanceDTO]
    var profile: ProfileDTO?

    static func empty(now: Date = Date()) -> AccountSnapshot {
        AccountSnapshot(updatedAt: now, loads: [], paychecks: [], diesel: [], maintenance: [], profile: nil)
    }
}

struct LoadDTO: Codable, Equatable {
    var id: UUID
    var tripId: String
    var date: Date
    var totalRate: Double
    var totalMiles: Double
    var pointA: String?
    var pointB: String?
    var puCount: Int
    var delCount: Int
    var stopCount: Int
    var weekNumber: Int
    var year: Int
    var parsedAt: Date
    var updatedAt: Date
    var isDispute: Bool
    var disputeCompleted: Bool
    var disputeResponseDate: Date?
    var disputeAmount: Double?
    var actualFinishDate: Date?
    var firstPickupAt: Date?
    var lastDeliveryAt: Date?
    var durationDays: Double
    var isDeleted: Bool = false
    var stops: [StopDTO]
    var penalties: [PenaltyDTO]
}

struct StopDTO: Codable, Equatable {
    var id: UUID
    var type: String
    var stopNumber: Int
    var puNumber: String?
    var note: String?
    var facility: String?
    var fullAddress: String
    var city: String
    var state: String
    var zip: String?
    var scheduledTime: Date?
    var scheduledTimeRaw: String?
    var timezone: String?
}

struct PenaltyDTO: Codable, Equatable {
    var id: UUID
    var summary: String
    var amount: Double
    var date: Date
}

struct PaycheckDTO: Codable, Equatable {
    var id: UUID
    var amount: Double
    var date: Date
    var company: String?
    var notes: String?
    var weekNumber: Int
    var year: Int
    var updatedAt: Date
    var isDeleted: Bool = false
}

struct DieselDTO: Codable, Equatable {
    var id: UUID
    var gallons: Double
    var totalCost: Double
    var pricePerGallon: Double
    var location: String?
    var state: String?
    var date: Date
    var odometer: Int?
    var updatedAt: Date
    var isDeleted: Bool = false
}

struct MaintenanceDTO: Codable, Equatable {
    var id: UUID
    var title: String
    var dueDate: Date?
    var dueOdometer: Int?
    var completedDate: Date?
    var cost: Double?
    var notes: String?
    var isArchived: Bool
    var updatedAt: Date
    var isDeleted: Bool = false
}

struct ProfileDTO: Codable, Equatable {
    var id: UUID
    var name: String?
    var carrier: String?
    var truckModel: String?
    var truckYear: Int?
    var licensePlate: String?
    var homeState: String?
    var weeklyGoal: Double
    var updatedAt: Date
}

extension JSONEncoder {
    /// Backup files: ISO-8601 dates, snake_case keys.
    static let snapshot: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}

extension JSONDecoder {
    static let snapshot: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
