import Foundation

/// Android `BackupData`. Photos, scans and receipt bytes are not in the file.
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
        originPlatform: String? = nil
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

    public init(
        loads: [BackupLoad] = [],
        paychecks: [BackupPaycheck] = [],
        diesel: [BackupDiesel] = [],
        maintenanceTasks: [BackupMaintenanceTask] = [],
        maintenanceArchive: [BackupMaintenanceArchive] = [],
        appSettings: BackupAppSettings? = nil
    ) {
        self.loads = loads
        self.paychecks = paychecks
        self.diesel = diesel
        self.maintenanceTasks = maintenanceTasks
        self.maintenanceArchive = maintenanceArchive
        self.appSettings = appSettings
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
