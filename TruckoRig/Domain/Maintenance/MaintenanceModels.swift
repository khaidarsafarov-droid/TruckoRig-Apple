import Foundation

/// Miles since the last service, or a calendar date. Port of `MaintenanceReminderType`.
public enum MaintenanceReminderType: String, Codable, Sendable, Equatable {
    case miles = "MILES"
    case date = "DATE"
}

/// One ТО reminder. Field names match Android `MaintenanceTask`.
///
/// `id` is a UUID string. Android uses a Room autoincrement `Long`; iOS keeps the UUID primary
/// keys the rest of the journal already uses.
public struct MaintenanceTask: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var startDate: String
    public var reminderType: MaintenanceReminderType
    public var intervalMiles: Double?
    public var odometerAtStart: Double?
    public var dueDate: String?
    public var isCompleted: Bool
    public var completedAt: Int64?
    public var notifiedAt: Int64?
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(
        id: String = UUID().uuidString,
        title: String,
        startDate: String,
        reminderType: MaintenanceReminderType,
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

/// One saved service line. Several lines entered together form a visit.
public struct MaintenanceArchiveEntry: Equatable, Identifiable, Sendable {
    public var id: String
    public var serviceName: String
    public var serviceDate: String
    public var description: String
    public var amount: MoneyCents
    public var photoPath: String?
    public var ocrText: String?
    public var createdAt: Int64

    public init(
        id: String = UUID().uuidString,
        serviceName: String = "",
        serviceDate: String,
        description: String,
        amount: MoneyCents,
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

/// Progress snapshot for a miles-based or date-based ТО task.
public struct MaintenanceProgress: Equatable, Sendable {
    public var task: MaintenanceTask
    public var milesDrivenSinceStart: Double
    public var estimatedOdometer: Double?
    public var targetOdometer: Double?
    public var milesRemaining: Double?
    public var daysRemaining: Int64?
    public var isDue: Bool
    public var loadsCounted: Int
    public var progressFraction: Double

    public init(
        task: MaintenanceTask,
        milesDrivenSinceStart: Double,
        estimatedOdometer: Double?,
        targetOdometer: Double?,
        milesRemaining: Double?,
        daysRemaining: Int64?,
        isDue: Bool,
        loadsCounted: Int = 0,
        progressFraction: Double = 0
    ) {
        self.task = task
        self.milesDrivenSinceStart = milesDrivenSinceStart
        self.estimatedOdometer = estimatedOdometer
        self.targetOdometer = targetOdometer
        self.milesRemaining = milesRemaining
        self.daysRemaining = daysRemaining
        self.isDue = isDue
        self.loadsCounted = loadsCounted
        self.progressFraction = progressFraction
    }
}

/// One shop visit: several saved services that were entered (or scanned) together.
public struct MaintenanceVisit: Equatable, Sendable {
    public var shopName: String
    public var serviceDate: String
    public var photoPath: String?
    public var createdAt: Int64
    public var lines: [MaintenanceArchiveEntry]

    public var total: Double { lines.reduce(MoneyCents.zero) { $0 + $1.amount }.dollars }
    public var ids: [String] { lines.map(\.id) }

    public init(
        shopName: String,
        serviceDate: String,
        photoPath: String?,
        createdAt: Int64,
        lines: [MaintenanceArchiveEntry]
    ) {
        self.shopName = shopName
        self.serviceDate = serviceDate
        self.photoPath = photoPath
        self.createdAt = createdAt
        self.lines = lines
    }
}
