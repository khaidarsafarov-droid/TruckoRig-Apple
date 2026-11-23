import Foundation

public struct BackupMaintenanceTask: Equatable, Sendable {
    public var id: Int64
    public var title: String
    public var startDate: String
    public var reminderType: String
    public var intervalMiles: Double?
    public var odometerAtStart: Double?
    public var dueDate: String?
    public var isCompleted: Bool
    public var completedAt: Int64?
    public var notifiedAt: Int64?
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: Int64 = 0,
        title: String = "",
        startDate: String = "",
        reminderType: String = "DATE",
        intervalMiles: Double? = nil,
        odometerAtStart: Double? = nil,
        dueDate: String? = nil,
        isCompleted: Bool = false,
        completedAt: Int64? = nil,
        notifiedAt: Int64? = nil,
        createdAt: Int64 = 0,
        updatedAt: Int64 = 0
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.reminderType = reminderType
        self.intervalMiles = intervalMiles
        self.odometerAtStart = odometerAtStart
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.notifiedAt = notifiedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupMaintenanceArchive: Equatable, Sendable {
    public var id: Int64
    public var serviceName: String
    public var serviceDate: String
    public var description: String
    /// Dollars, not cents. Android writes `amount.cents / 100.0`.
    public var amount: Double
    public var photoPath: String?
    public var ocrText: String?
    public var createdAt: Int64

    public init(
        id: Int64 = 0,
        serviceName: String = "",
        serviceDate: String = "",
        description: String = "",
        amount: Double = 0,
        photoPath: String? = nil,
        ocrText: String? = nil,
        createdAt: Int64 = 0
    ) {
        self.id = id
        self.serviceName = serviceName
        self.serviceDate = serviceDate
        self.description = description
        self.amount = amount
        self.photoPath = photoPath
        self.ocrText = ocrText
        self.createdAt = createdAt
    }
}
