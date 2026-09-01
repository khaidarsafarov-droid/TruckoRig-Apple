import Foundation

// MARK: - Auth payloads

struct AppleSignInRequest: Encodable {
    var identityToken: String
    var fullName: String?
    var platform = "ios"
}

struct EmailCredentials: Encodable {
    var email: String
    var password: String
}

struct RefreshRequest: Encodable {
    var refreshToken: String
}

struct AuthResponse: Decodable {
    var userId: String
    var email: String?
    var displayName: String?
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
}

// MARK: - Devices

struct DeviceRegistration: Encodable {
    var deviceId: String
    var platform = "ios"
}

struct PushTokenUpdate: Encodable {
    var deviceId: String
    var token: String
    var platform = "ios"
}

// MARK: - Media

struct MediaUploadRequest: Encodable {
    var fileName: String
    var contentType: String
    var byteSize: Int
    var kind: String
}

/// Presigned destination for a direct-to-storage upload.
///
/// Media bytes never pass through the backend: the client PUTs straight to object storage and then
/// confirms. The URL is a credential — never log it.
struct MediaUploadTicket: Decodable {
    var uploadURL: URL
    var objectKey: String
    var headers: [String: String]?
}

struct MediaCompleteRequest: Encodable {
    var objectKey: String
    var entityType: String
    var entityId: String
}

// MARK: - Sync

/// Server-side change marker. The client keeps the last one it applied so a sync only has to move
/// what changed since.
struct SyncCursor: Codable, Equatable {
    var value: String
    var updatedAt: Date

    static let empty = SyncCursor(value: "", updatedAt: Date(timeIntervalSince1970: 0))
}

/// Whole-account payload exchanged with the backend.
///
/// Conflicts resolve last-write-wins on `updatedAt` per row, which is the same rule the Android
/// client applies, so the two can share an account without ping-ponging edits.
struct AccountCloudSnapshot: Codable, Equatable {
    var schemaVersion: Int = 1
    var updatedAt: Date
    var loads: [LoadDTO]
    var paychecks: [PaycheckDTO]
    var diesel: [DieselDTO]
    var maintenance: [MaintenanceDTO]
    var profile: ProfileDTO?

    static func empty(now: Date = Date()) -> AccountCloudSnapshot {
        AccountCloudSnapshot(updatedAt: now, loads: [], paychecks: [], diesel: [], maintenance: [], profile: nil)
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
