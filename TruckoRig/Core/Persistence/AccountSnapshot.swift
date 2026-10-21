import Foundation

/// Whole-account payload for JSON backup and restore.
///
/// Conflicts resolve last-write-wins on `updatedAt` per row. The on-disk shape stays compatible
/// with files previously exported from this app.
struct AccountSnapshot: Equatable {
    var schemaVersion: Int
    var updatedAt: Date
    var loads: [LoadDTO]
    var paychecks: [PaycheckDTO]
    var diesel: [DieselDTO]
    var maintenance: [MaintenanceDTO]
    var profile: ProfileDTO?
    var maintenanceArchive: [MaintenanceArchiveDTO]
    /// Absent on backups written before other expenses existed. Nil means "leave the phone's rows".
    var expenses: [MiscExpenseDTO]?
    var perDiemOverrides: [PerDiemOverrideDTO]?

    init(
        schemaVersion: Int = 2,
        updatedAt: Date,
        loads: [LoadDTO],
        paychecks: [PaycheckDTO],
        diesel: [DieselDTO],
        maintenance: [MaintenanceDTO],
        profile: ProfileDTO?,
        maintenanceArchive: [MaintenanceArchiveDTO] = [],
        expenses: [MiscExpenseDTO]? = nil,
        perDiemOverrides: [PerDiemOverrideDTO]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.loads = loads
        self.paychecks = paychecks
        self.diesel = diesel
        self.maintenance = maintenance
        self.profile = profile
        self.maintenanceArchive = maintenanceArchive
        self.expenses = expenses
        self.perDiemOverrides = perDiemOverrides
    }

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
    var grossAmount: Double?
    var driverName: String?
    var rawText: String?
    var sourceFileName: String?
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
    var discountPricePerGallon: Double?
    var rawText: String?
    var receiptFileName: String?
    var sourceFileName: String?
}

/// Android `MaintenanceTask` fields. A stage-1 backup (no `reminderType`) is converted on decode.
struct MaintenanceDTO: Equatable {
    var id: String
    var title: String
    var startDate: String
    var reminderType: String
    var intervalMiles: Double?
    var odometerAtStart: Double?
    var dueDate: String?
    var isCompleted: Bool
    var completedAt: Int64?
    var notifiedAt: Int64?
    var createdAt: Int64
    var updatedAt: Int64
    var isDeleted: Bool
    /// Cost or notes from a stage-1 row. Applied once, when the task is inserted.
    var legacyArchive: MaintenanceArchiveDTO?

    init(task: MaintenanceTask, isDeleted: Bool = false) {
        id = task.id
        title = task.title
        startDate = task.startDate
        reminderType = task.reminderType.rawValue
        intervalMiles = task.intervalMiles
        odometerAtStart = task.odometerAtStart
        dueDate = task.dueDate
        isCompleted = task.isCompleted
        completedAt = task.completedAt
        notifiedAt = task.notifiedAt
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        self.isDeleted = isDeleted
        legacyArchive = nil
    }

    func makeTask() -> MaintenanceTask {
        MaintenanceTask(
            id: id,
            title: title,
            startDate: startDate,
            reminderType: MaintenanceReminderType(rawValue: reminderType) ?? .date,
            intervalMiles: intervalMiles,
            odometerAtStart: odometerAtStart,
            dueDate: dueDate,
            isCompleted: isCompleted,
            completedAt: completedAt,
            notifiedAt: notifiedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct MaintenanceArchiveDTO: Equatable {
    var id: String
    var serviceName: String
    var serviceDate: String
    var description: String
    var amountCents: Int64
    var photoPath: String?
    var ocrText: String?
    var createdAt: Int64
    var isDeleted: Bool

    init(entry: MaintenanceArchiveEntry, isDeleted: Bool = false) {
        id = entry.id
        serviceName = entry.serviceName
        serviceDate = entry.serviceDate
        description = entry.description
        amountCents = entry.amount.cents
        photoPath = entry.photoPath
        ocrText = entry.ocrText
        createdAt = entry.createdAt
        self.isDeleted = isDeleted
    }

    func makeEntry() -> MaintenanceArchiveEntry {
        MaintenanceArchiveEntry(
            id: id,
            serviceName: serviceName,
            serviceDate: serviceDate,
            description: description,
            amount: MoneyCents(cents: amountCents),
            photoPath: photoPath,
            ocrText: ocrText,
            createdAt: createdAt
        )
    }
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
    var role: String?
}

extension AccountSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, updatedAt, loads, paychecks, diesel, maintenance, profile, maintenanceArchive, expenses, perDiemOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        loads = try container.decode([LoadDTO].self, forKey: .loads)
        paychecks = try container.decode([PaycheckDTO].self, forKey: .paychecks)
        diesel = try container.decode([DieselDTO].self, forKey: .diesel)
        maintenance = try container.decode([MaintenanceDTO].self, forKey: .maintenance)
        profile = try container.decodeIfPresent(ProfileDTO.self, forKey: .profile)
        maintenanceArchive = try container.decodeIfPresent([MaintenanceArchiveDTO].self, forKey: .maintenanceArchive) ?? []
        expenses = try container.decodeIfPresent([MiscExpenseDTO].self, forKey: .expenses)
        perDiemOverrides = try container.decodeIfPresent([PerDiemOverrideDTO].self, forKey: .perDiemOverrides)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(loads, forKey: .loads)
        try container.encode(paychecks, forKey: .paychecks)
        try container.encode(diesel, forKey: .diesel)
        try container.encode(maintenance, forKey: .maintenance)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encode(maintenanceArchive, forKey: .maintenanceArchive)
        try container.encodeIfPresent(expenses, forKey: .expenses)
        try container.encodeIfPresent(perDiemOverrides, forKey: .perDiemOverrides)
    }
}

extension MaintenanceDTO: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, startDate, reminderType, intervalMiles, odometerAtStart, dueDate
        case isCompleted, completedAt, notifiedAt, createdAt, updatedAt, isDeleted
        case dueOdometer, completedDate, cost, notes, isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        if container.contains(.reminderType) || container.contains(.startDate) {
            startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ?? ""
            reminderType = try container.decodeIfPresent(String.self, forKey: .reminderType) ?? MaintenanceReminderType.date.rawValue
            intervalMiles = try container.decodeIfPresent(Double.self, forKey: .intervalMiles)
            odometerAtStart = try container.decodeIfPresent(Double.self, forKey: .odometerAtStart)
            dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
            isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
            completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAt)
            notifiedAt = try container.decodeIfPresent(Int64.self, forKey: .notifiedAt)
            createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
            updatedAt = try container.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
            legacyArchive = nil
            return
        }
        let due = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        let completed = try container.decodeIfPresent(Date.self, forKey: .completedDate)
        let updated = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let imported = MaintenanceLegacyImport.convert(
            MaintenanceLegacyImport.Stub(
                id: id,
                title: title,
                dueDateISO: due.map { MaintenanceMileage.isoDay($0, calendar: calendar) },
                dueOdometer: try container.decodeIfPresent(Int.self, forKey: .dueOdometer),
                completedAtMillis: completed.map { Int64($0.timeIntervalSince1970 * 1000) },
                cost: try container.decodeIfPresent(Double.self, forKey: .cost),
                notes: try container.decodeIfPresent(String.self, forKey: .notes),
                updatedAtMillis: Int64(updated.timeIntervalSince1970 * 1000)
            ),
            fallbackStartDate: MaintenanceMileage.isoDay(due ?? completed ?? updated, calendar: calendar)
        )
        self = MaintenanceDTO(task: imported.task, isDeleted: isDeleted)
        legacyArchive = imported.archive.map { MaintenanceArchiveDTO(entry: $0) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(reminderType, forKey: .reminderType)
        try container.encodeIfPresent(intervalMiles, forKey: .intervalMiles)
        try container.encodeIfPresent(odometerAtStart, forKey: .odometerAtStart)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(notifiedAt, forKey: .notifiedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isDeleted, forKey: .isDeleted)
    }
}

extension MaintenanceArchiveDTO: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, serviceName, serviceDate, description, amountCents, photoPath, ocrText, createdAt, isDeleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        serviceName = try container.decodeIfPresent(String.self, forKey: .serviceName) ?? ""
        serviceDate = try container.decode(String.self, forKey: .serviceDate)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        amountCents = try container.decodeIfPresent(Int64.self, forKey: .amountCents) ?? 0
        photoPath = try container.decodeIfPresent(String.self, forKey: .photoPath)
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        createdAt = try container.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
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


struct MiscExpenseDTO: Codable, Equatable {
    var id: UUID
    var amount: Double
    var expenseDescription: String
    var date: Date
    var receiptFileName: String?
    var updatedAt: Date
    var isDeleted: Bool = false
}

struct PerDiemOverrideDTO: Codable, Equatable {
    var isoDate: String
    var included: Bool
}
