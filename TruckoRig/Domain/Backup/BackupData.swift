import Foundation

/// Android `BackupData`. Photos, scans and receipt bytes are not in the file.
///
/// `miscExpenses` and `perDiemOverrides` are optional. `nil` means the file does not carry
/// them (older files from either platform), and restore leaves those local rows alone.
public struct BackupData: Equatable, Sendable {
    public var schemaVersion: Int
    public var version: Int
    public var exportedAt: Int64
    public var accountId: String?
    public var loads: [BackupLoad]
    public var paychecks: [BackupPaycheck]
    public var diesel: [BackupDiesel]
    public var maintenanceTasks: [BackupMaintenanceTask]
    public var maintenanceArchive: [BackupMaintenanceArchive]
    public var appSettings: BackupAppSettings?
    /// Optional. Omitted when empty so a manual export stays byte-compatible with Android Gson.
    /// iCloud writes the device model and `ios`. Android ignores unknown keys.
    public var originDevice: String?
    public var originPlatform: String?
    public var miscExpenses: [BackupMiscExpense]?
    public var perDiemOverrides: [BackupPerDiemOverride]?

    public init(
        schemaVersion: Int = 0,
        version: Int = 0,
        exportedAt: Int64 = 0,
        accountId: String? = nil,
        loads: [BackupLoad] = [],
        paychecks: [BackupPaycheck] = [],
        diesel: [BackupDiesel] = [],
        maintenanceTasks: [BackupMaintenanceTask] = [],
        maintenanceArchive: [BackupMaintenanceArchive] = [],
        appSettings: BackupAppSettings? = nil,
        originDevice: String? = nil,
        originPlatform: String? = nil,
        miscExpenses: [BackupMiscExpense]? = nil,
        perDiemOverrides: [BackupPerDiemOverride]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.exportedAt = exportedAt
        self.accountId = accountId
        self.loads = loads
        self.paychecks = paychecks
        self.diesel = diesel
        self.maintenanceTasks = maintenanceTasks
        self.maintenanceArchive = maintenanceArchive
        self.appSettings = appSettings
        self.originDevice = originDevice
        self.originPlatform = originPlatform
        self.miscExpenses = miscExpenses
        self.perDiemOverrides = perDiemOverrides
    }
}

/// Android `BackupMiscExpense`. `uuid` is the iOS row id; Android ignores the key.
public struct BackupMiscExpense: Equatable, Sendable {
    public var id: Int
    public var amountCents: Int64
    public var description: String
    /// `yyyy-MM-dd`.
    public var date: String
    public var receiptPhotoPath: String?
    public var createdAt: Int64
    public var updatedAt: Int64
    public var uuid: String?

    public init(
        id: Int = 0,
        amountCents: Int64 = 0,
        description: String = "",
        date: String = "",
        receiptPhotoPath: String? = nil,
        createdAt: Int64 = 0,
        updatedAt: Int64 = 0,
        uuid: String? = nil
    ) {
        self.id = id
        self.amountCents = amountCents
        self.description = description
        self.date = date
        self.receiptPhotoPath = receiptPhotoPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.uuid = uuid
    }
}

/// Android `BackupPerDiemOverride`: one manual per-diem day (`yyyy-MM-dd`).
public struct BackupPerDiemOverride: Equatable, Sendable {
    public var date: String
    public var included: Bool

    public init(date: String = "", included: Bool = false) {
        self.date = date
        self.included = included
    }
}

public enum BackupDecodeError: Error, Equatable, Sendable {
    case invalidFormat
    case corrupted
    case schemaTooNew(Int)
}

public struct BackupJournal: Equatable, Sendable {
    public var loads: [BackupLoad]
    public var paychecks: [BackupPaycheck]
    public var diesel: [BackupDiesel]
    public var maintenanceTasks: [BackupMaintenanceTask]
    public var maintenanceArchive: [BackupMaintenanceArchive]
    public var appSettings: BackupAppSettings?
    public var miscExpenses: [BackupMiscExpense]
    public var perDiemOverrides: [BackupPerDiemOverride]

    public init(
        loads: [BackupLoad] = [],
        paychecks: [BackupPaycheck] = [],
        diesel: [BackupDiesel] = [],
        maintenanceTasks: [BackupMaintenanceTask] = [],
        maintenanceArchive: [BackupMaintenanceArchive] = [],
        appSettings: BackupAppSettings? = nil,
        miscExpenses: [BackupMiscExpense] = [],
        perDiemOverrides: [BackupPerDiemOverride] = []
    ) {
        self.loads = loads
        self.paychecks = paychecks
        self.diesel = diesel
        self.maintenanceTasks = maintenanceTasks
        self.maintenanceArchive = maintenanceArchive
        self.appSettings = appSettings
        self.miscExpenses = miscExpenses
        self.perDiemOverrides = perDiemOverrides
    }
}

public enum BackupRestoreRejection: Equatable, Sendable {
    case wrongAccount
    case unboundAccount
    case schemaTooNew(Int)
    case corrupted
    case invalidFormat
    case tooLarge
}

public enum BackupRestoreOutcome: Equatable, Sendable {
    case replaced(BackupJournal)
    case rejected(BackupRestoreRejection)
}
