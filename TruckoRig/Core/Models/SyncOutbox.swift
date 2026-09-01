import Foundation
import SwiftData

/// Entity kinds that participate in cloud sync.
enum SyncEntityType: String, Codable, CaseIterable {
    case load
    case paycheck
    case diesel
    case maintenance
    case photo
    case scan
    case profile
}

enum SyncOperation: String, Codable, CaseIterable {
    case create
    case update
    case delete
}

/// A local change waiting to reach the server.
///
/// Every mutation writes here in the same transaction as the change itself, so a crash or an
/// offline stretch can never lose the fact that something needs uploading.
@Model
final class SyncOutbox {
    @Attribute(.unique) var id: UUID
    var entityType: SyncEntityType
    var entityId: UUID
    var operation: SyncOperation
    var timestamp: Date
    var retryCount: Int
    var lastAttemptAt: Date?
    /// Last failure, for the settings diagnostics row. Never contains tokens or payloads.
    var lastError: String?

    init(
        id: UUID = UUID(),
        entityType: SyncEntityType,
        entityId: UUID,
        operation: SyncOperation,
        timestamp: Date = Date(),
        retryCount: Int = 0,
        lastAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.timestamp = timestamp
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
        self.lastError = lastError
    }

}
