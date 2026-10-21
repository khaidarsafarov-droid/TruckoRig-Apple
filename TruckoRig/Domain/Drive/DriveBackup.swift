import Foundation

/// Android `BackupSchema`.
public enum DriveBackupSchema {
    public static let current = 2
    public static let v1 = 1
    public static let v2 = 2
    public static let jsonMIME = "application/json"

    public static func resolve(schemaVersion: Int, version: Int) -> Int {
        if schemaVersion > 0 { return schemaVersion }
        if version > 0 { return version }
        return v1
    }
}

public struct DriveStop: Equatable, Sendable {
    public var id: Int
    public var loadId: String
    public var stopNumber: Int
    public var type: String
    public var puNumber: String?
    public var note: String?
    public var scheduledTime: String
    public var timezone: String
    public var facilityCode: String?
    public var fullAddress: String
    public var city: String
    public var state: String
    public var zip: String

    public init(
        id: Int = 0,
        loadId: String = "",
        stopNumber: Int = 0,
        type: String = "PU",
        puNumber: String? = nil,
        note: String? = nil,
        scheduledTime: String = "",
        timezone: String = "",
        facilityCode: String? = nil,
        fullAddress: String = "",
        city: String = "",
        state: String = "",
        zip: String = ""
    ) {
        self.id = id
        self.loadId = loadId
        self.stopNumber = stopNumber
        self.type = type
        self.puNumber = puNumber
        self.note = note
        self.scheduledTime = scheduledTime
        self.timezone = timezone
        self.facilityCode = facilityCode
        self.fullAddress = fullAddress
        self.city = city
        self.state = state
        self.zip = zip
    }
}

public struct DrivePenalty: Equatable, Sendable {
    public var id: Int
    public var loadId: String
    public var description: String
    /// Unboxed `Money` cents. Gson writes a JSON number, not `{"cents":…}`.
    public var amountCents: Int64

    public init(id: Int = 0, loadId: String = "", description: String = "", amountCents: Int64 = 0) {
        self.id = id
        self.loadId = loadId
        self.description = description
        self.amountCents = amountCents
    }
}

public struct DriveLoad: Equatable, Sendable {
    public var id: String
    public var tripId: String
    public var date: String
    public var totalRateCents: Int64
    public var totalMiles: Double
    public var pointA: String
    public var pointB: String
    public var puCount: Int
    public var delCount: Int
    public var weekNumber: Int
    public var year: Int
    public var rawMessage: String
    public var parsedAt: Int64
    public var updatedAt: Int64
    public var route: String
    public var firstPuCityState: String
    public var lastDelCityState: String
    public var durationDays: Double
    public var paceCents: Int64
    public var stopCount: Int
    public var isDispute: Bool
    public var disputeResponseDate: String?
    public var disputeCompleted: Bool
    public var disputeAmountCents: Int64?
    public var disputeApplyToLoad: Bool
    public var disputeAmountApplied: Bool
    public var actualFinishDate: String?
    public var stops: [DriveStop]
    public var penalties: [DrivePenalty]
    public var equipmentType: String?
    public var deadheadMiles: Double

    public init(
        id: String = "",
        tripId: String = "",
        date: String = "",
        totalRateCents: Int64 = 0,
        totalMiles: Double = 0,
        pointA: String = "",
        pointB: String = "",
        puCount: Int = 0,
        delCount: Int = 0,
        weekNumber: Int = 0,
        year: Int = 0,
        rawMessage: String = "",
        parsedAt: Int64 = 0,
        updatedAt: Int64 = 0,
        route: String = "",
        firstPuCityState: String = "",
        lastDelCityState: String = "",
        durationDays: Double = 0,
        paceCents: Int64 = 0,
        stopCount: Int = 0,
        isDispute: Bool = false,
        disputeResponseDate: String? = nil,
        disputeCompleted: Bool = false,
        disputeAmountCents: Int64? = nil,
        disputeApplyToLoad: Bool = false,
        disputeAmountApplied: Bool = false,
        actualFinishDate: String? = nil,
        stops: [DriveStop] = [],
        penalties: [DrivePenalty] = [],
        equipmentType: String? = nil,
        deadheadMiles: Double = 0
    ) {
        self.id = id
        self.tripId = tripId
        self.date = date
        self.totalRateCents = totalRateCents
        self.totalMiles = totalMiles
        self.pointA = pointA
        self.pointB = pointB
        self.puCount = puCount
        self.delCount = delCount
        self.weekNumber = weekNumber
        self.year = year
        self.rawMessage = rawMessage
        self.parsedAt = parsedAt
        self.updatedAt = updatedAt
        self.route = route
        self.firstPuCityState = firstPuCityState
        self.lastDelCityState = lastDelCityState
        self.durationDays = durationDays
        self.paceCents = paceCents
        self.stopCount = stopCount
        self.isDispute = isDispute
        self.disputeResponseDate = disputeResponseDate
        self.disputeCompleted = disputeCompleted
        self.disputeAmountCents = disputeAmountCents
        self.disputeApplyToLoad = disputeApplyToLoad
        self.disputeAmountApplied = disputeAmountApplied
        self.actualFinishDate = actualFinishDate
        self.stops = stops
        self.penalties = penalties
        self.equipmentType = equipmentType
        self.deadheadMiles = deadheadMiles
    }
}

public struct DrivePaycheck: Equatable, Sendable {
    public var id: Int
    public var weekNumber: Int
    public var year: Int
    public var weekLabel: String
    public var weekStartDate: String
    public var weekEndDate: String
    public var driverName: String?
    /// Nullable `Money` is boxed. Gson writes `{"cents":…}`.
    public var grossAmountCents: Int64?
    public var netAmountCents: Int64
    public var rawExtractedText: String
    public var sourceFileName: String?
    public var addedAt: Int64
    public var sourceFilePath: String?

    public init(
        id: Int = 0,
        weekNumber: Int = 0,
        year: Int = 0,
        weekLabel: String = "",
        weekStartDate: String = "",
        weekEndDate: String = "",
        driverName: String? = nil,
        grossAmountCents: Int64? = nil,
        netAmountCents: Int64 = 0,
        rawExtractedText: String = "",
        sourceFileName: String? = nil,
        addedAt: Int64 = 0,
        sourceFilePath: String? = nil
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.year = year
        self.weekLabel = weekLabel
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.driverName = driverName
        self.grossAmountCents = grossAmountCents
        self.netAmountCents = netAmountCents
        self.rawExtractedText = rawExtractedText
        self.sourceFileName = sourceFileName
        self.addedAt = addedAt
        self.sourceFilePath = sourceFilePath
    }
}

public struct DriveDiesel: Equatable, Sendable {
    public var id: Int
    public var weekNumber: Int
    public var year: Int
    public var weekLabel: String
    public var weekStartDate: String
    public var weekEndDate: String
    public var totalAmountCents: Int64
    public var gallons: Double?
    /// Nullable `UnitPrice` is boxed. Gson writes `{"thousandths":…}`.
    public var pricePerGallonThousandths: Int64?
    public var discountPricePerGallonThousandths: Int64?
    public var location: String?
    public var rawExtractedText: String
    public var sourceFileName: String?
    public var addedAt: Int64

    public init(
        id: Int = 0,
        weekNumber: Int = 0,
        year: Int = 0,
        weekLabel: String = "",
        weekStartDate: String = "",
        weekEndDate: String = "",
        totalAmountCents: Int64 = 0,
        gallons: Double? = nil,
        pricePerGallonThousandths: Int64? = nil,
        discountPricePerGallonThousandths: Int64? = nil,
        location: String? = nil,
        rawExtractedText: String = "",
        sourceFileName: String? = nil,
        addedAt: Int64 = 0
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.year = year
        self.weekLabel = weekLabel
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.totalAmountCents = totalAmountCents
        self.gallons = gallons
        self.pricePerGallonThousandths = pricePerGallonThousandths
        self.discountPricePerGallonThousandths = discountPricePerGallonThousandths
        self.location = location
        self.rawExtractedText = rawExtractedText
        self.sourceFileName = sourceFileName
        self.addedAt = addedAt
    }
}

public struct DriveMaintenanceTask: Equatable, Sendable {
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

public struct DriveMaintenanceArchive: Equatable, Sendable {
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

public struct DriveAppSettings: Equatable, Sendable {
    public var themeModeOrdinal: Int?
    public var languageOrdinal: Int?
    public var reduceMotion: Bool?
    public var oledDark: Bool?
    public var dynamicColor: Bool?
    public var parserAutoUpdate: Bool?
    public var parserPriceThresholdPercent: Double?
    public var quietHoursEnabled: Bool?
    public var quietHoursStart: Int?
    public var quietHoursEnd: Int?
    public var notifyMissingWeek: Bool?
    public var notifyMaintenance: Bool?
    public var lastEquipmentType: String?
    public var weeklyProfitGoal: Double?
    public var rpmMinProfit: Double?
    public var rpmTargetProfit: Double?
    /// Read for old files. Never written. Android does not restore it.
    public var telegramChatId: Int64?
    public var loadWeekStartDay: Int?
    public var dieselWeekStartDay: Int?

    public init(
        themeModeOrdinal: Int? = nil,
        languageOrdinal: Int? = nil,
        reduceMotion: Bool? = nil,
        oledDark: Bool? = nil,
        dynamicColor: Bool? = nil,
        parserAutoUpdate: Bool? = nil,
        parserPriceThresholdPercent: Double? = nil,
        quietHoursEnabled: Bool? = nil,
        quietHoursStart: Int? = nil,
        quietHoursEnd: Int? = nil,
        notifyMissingWeek: Bool? = nil,
        notifyMaintenance: Bool? = nil,
        lastEquipmentType: String? = nil,
        weeklyProfitGoal: Double? = nil,
        rpmMinProfit: Double? = nil,
        rpmTargetProfit: Double? = nil,
        telegramChatId: Int64? = nil,
        loadWeekStartDay: Int? = nil,
        dieselWeekStartDay: Int? = nil
    ) {
        self.themeModeOrdinal = themeModeOrdinal
        self.languageOrdinal = languageOrdinal
        self.reduceMotion = reduceMotion
        self.oledDark = oledDark
        self.dynamicColor = dynamicColor
        self.parserAutoUpdate = parserAutoUpdate
        self.parserPriceThresholdPercent = parserPriceThresholdPercent
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.notifyMissingWeek = notifyMissingWeek
        self.notifyMaintenance = notifyMaintenance
        self.lastEquipmentType = lastEquipmentType
        self.weeklyProfitGoal = weeklyProfitGoal
        self.rpmMinProfit = rpmMinProfit
        self.rpmTargetProfit = rpmTargetProfit
        self.telegramChatId = telegramChatId
        self.loadWeekStartDay = loadWeekStartDay
        self.dieselWeekStartDay = dieselWeekStartDay
    }
}

/// Android `BackupData`. Photos, scans and receipt bytes are not in the file.
public struct DriveBackup: Equatable, Sendable {
    public var schemaVersion: Int
    public var version: Int
    public var exportedAt: Int64
    public var accountId: String?
    public var loads: [DriveLoad]
    public var paychecks: [DrivePaycheck]
    public var diesel: [DriveDiesel]
    public var maintenanceTasks: [DriveMaintenanceTask]
    public var maintenanceArchive: [DriveMaintenanceArchive]
    public var appSettings: DriveAppSettings?

    public init(
        schemaVersion: Int = 0,
        version: Int = 0,
        exportedAt: Int64 = 0,
        accountId: String? = nil,
        loads: [DriveLoad] = [],
        paychecks: [DrivePaycheck] = [],
        diesel: [DriveDiesel] = [],
        maintenanceTasks: [DriveMaintenanceTask] = [],
        maintenanceArchive: [DriveMaintenanceArchive] = [],
        appSettings: DriveAppSettings? = nil
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
    }
}

public enum DriveBackupDecodeError: Error, Equatable, Sendable {
    case invalidFormat
    case corrupted
    case schemaTooNew(Int)
}

public struct DriveJournal: Equatable, Sendable {
    public var loads: [DriveLoad]
    public var paychecks: [DrivePaycheck]
    public var diesel: [DriveDiesel]
    public var maintenanceTasks: [DriveMaintenanceTask]
    public var maintenanceArchive: [DriveMaintenanceArchive]
    public var appSettings: DriveAppSettings?

    public init(
        loads: [DriveLoad] = [],
        paychecks: [DrivePaycheck] = [],
        diesel: [DriveDiesel] = [],
        maintenanceTasks: [DriveMaintenanceTask] = [],
        maintenanceArchive: [DriveMaintenanceArchive] = [],
        appSettings: DriveAppSettings? = nil
    ) {
        self.loads = loads
        self.paychecks = paychecks
        self.diesel = diesel
        self.maintenanceTasks = maintenanceTasks
        self.maintenanceArchive = maintenanceArchive
        self.appSettings = appSettings
    }
}

public enum DriveRestoreRejection: Equatable, Sendable {
    case wrongAccount
    case unboundAccount
    case schemaTooNew(Int)
    case corrupted
    case invalidFormat
    case tooLarge
}

public enum DriveRestoreOutcome: Equatable, Sendable {
    case replaced(DriveJournal)
    case rejected(DriveRestoreRejection)
}

/// JSON codec and full-replace restore. Gson omits nulls and does not HTML-escape.
public enum DriveBackupCodec {
    public static func hasExportableContent(_ backup: DriveBackup) -> Bool {
        !backup.loads.isEmpty
            || !backup.paychecks.isEmpty
            || !backup.diesel.isEmpty
            || !backup.maintenanceTasks.isEmpty
            || !backup.maintenanceArchive.isEmpty
    }

    public static func carriesMaintenance(_ backup: DriveBackup) -> Bool {
        DriveBackupSchema.resolve(schemaVersion: backup.schemaVersion, version: backup.version) >= DriveBackupSchema.v2
    }

    public static func encode(_ backup: DriveBackup) -> String {
        var fields: [(String, String)] = [
            ("schemaVersion", String(DriveBackupSchema.current)),
            ("version", String(DriveBackupSchema.current)),
            ("exportedAt", String(backup.exportedAt)),
        ]
        if let accountId = backup.accountId {
            fields.append(("accountId", DriveJSON.escape(accountId)))
        }
        fields.append(("loads", array(backup.loads.map(encodeLoad))))
        fields.append(("paychecks", array(backup.paychecks.map(encodePaycheck))))
        fields.append(("diesel", array(backup.diesel.map(encodeDiesel))))
        fields.append(("maintenanceTasks", array(backup.maintenanceTasks.map(encodeTask))))
        fields.append(("maintenanceArchive", array(backup.maintenanceArchive.map(encodeArchive))))
        if let settings = backup.appSettings {
            fields.append(("appSettings", encodeSettings(settings)))
        }
        return object(fields)
    }

    public static func decode(_ json: String) throws -> DriveBackup {
        let stripped = DriveJSON.stripBOM(json).trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { throw DriveBackupDecodeError.invalidFormat }
        let root: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: Data(stripped.utf8))
            guard let dictionary = object as? [String: Any] else { throw DriveBackupDecodeError.corrupted }
            root = dictionary
        } catch let error as DriveBackupDecodeError {
            throw error
        } catch {
            throw DriveBackupDecodeError.corrupted
        }
        let schema = DriveBackupSchema.resolve(
            schemaVersion: int(root["schemaVersion"]) ?? 0,
            version: int(root["version"]) ?? 0
        )
        if schema > DriveBackupSchema.current {
            throw DriveBackupDecodeError.schemaTooNew(schema)
        }
        return DriveBackup(
            schemaVersion: schema,
            version: schema,
            exportedAt: int64(root["exportedAt"]) ?? 0,
            accountId: string(root["accountId"]),
            loads: try array(root["loads"], encode: load),
            paychecks: try array(root["paychecks"], encode: paycheck),
            diesel: try array(root["diesel"], encode: diesel),
            maintenanceTasks: try array(root["maintenanceTasks"], encode: task),
            maintenanceArchive: try array(root["maintenanceArchive"], encode: archive),
            appSettings: root["appSettings"].map { settings($0) }
        )
    }

    public static func fromJSON(_ json: String) -> DriveBackup? {
        try? decode(json)
    }

    /// Full replace. Schema v1 leaves maintenance in place. Null settings leave the phone's settings.
    public static func restore(
        _ backup: DriveBackup,
        onto journal: DriveJournal,
        activeAccountId: String,
        allowUnboundAccount: Bool
    ) -> DriveRestoreOutcome {
        let account = backup.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let active = activeAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.isEmpty {
            if !allowUnboundAccount { return .rejected(.unboundAccount) }
        } else if !active.isEmpty && account != active {
            return .rejected(.wrongAccount)
        }
        var next = journal
        next.loads = backup.loads
        next.paychecks = backup.paychecks
        next.diesel = backup.diesel
        if carriesMaintenance(backup) {
            next.maintenanceTasks = backup.maintenanceTasks
            next.maintenanceArchive = backup.maintenanceArchive
        }
        if let settings = backup.appSettings {
            next.appSettings = settings
        }
        return .replaced(next)
    }

    public static func exceedsRestoreLimit(byteCount: Int) -> Bool {
        byteCount > DriveSchedule.maxRestoreBytes
    }

    // MARK: - Encode

    private static func encodeLoad(_ load: DriveLoad) -> String {
        var fields: [(String, String)] = [
            ("id", DriveJSON.escape(load.id)),
            ("tripId", DriveJSON.escape(load.tripId)),
            ("date", DriveJSON.escape(load.date)),
            ("totalRate", String(load.totalRateCents)),
            ("totalMiles", DriveJSON.renderDouble(load.totalMiles)),
            ("pointA", DriveJSON.escape(load.pointA)),
            ("pointB", DriveJSON.escape(load.pointB)),
            ("puCount", String(load.puCount)),
            ("delCount", String(load.delCount)),
            ("weekNumber", String(load.weekNumber)),
            ("year", String(load.year)),
            ("rawMessage", DriveJSON.escape(load.rawMessage)),
            ("parsedAt", String(load.parsedAt)),
            ("updatedAt", String(load.updatedAt)),
            ("route", DriveJSON.escape(load.route)),
            ("firstPuCityState", DriveJSON.escape(load.firstPuCityState)),
            ("lastDelCityState", DriveJSON.escape(load.lastDelCityState)),
            ("durationDays", DriveJSON.renderDouble(load.durationDays)),
            ("pace", String(load.paceCents)),
            ("stopCount", String(load.stopCount)),
            ("isDispute", bool(load.isDispute)),
        ]
        if let disputeResponseDate = load.disputeResponseDate {
            fields.append(("disputeResponseDate", DriveJSON.escape(disputeResponseDate)))
        }
        fields.append(("disputeCompleted", bool(load.disputeCompleted)))
        if let disputeAmountCents = load.disputeAmountCents {
            fields.append(("disputeAmount", boxedCents(disputeAmountCents)))
        }
        fields.append(("disputeApplyToLoad", bool(load.disputeApplyToLoad)))
        fields.append(("disputeAmountApplied", bool(load.disputeAmountApplied)))
        if let actualFinishDate = load.actualFinishDate {
            fields.append(("actualFinishDate", DriveJSON.escape(actualFinishDate)))
        }
        fields.append(("stops", array(load.stops.map(encodeStop))))
        fields.append(("penalties", array(load.penalties.map(encodePenalty))))
        if let equipmentType = load.equipmentType {
            fields.append(("equipmentType", DriveJSON.escape(equipmentType)))
        }
        fields.append(("deadheadMiles", DriveJSON.renderDouble(load.deadheadMiles)))
        return object(fields)
    }

    private static func encodeStop(_ stop: DriveStop) -> String {
        var fields: [(String, String)] = [
            ("id", String(stop.id)),
            ("loadId", DriveJSON.escape(stop.loadId)),
            ("stopNumber", String(stop.stopNumber)),
            ("type", DriveJSON.escape(stop.type)),
        ]
        if let puNumber = stop.puNumber { fields.append(("puNumber", DriveJSON.escape(puNumber))) }
        if let note = stop.note { fields.append(("note", DriveJSON.escape(note))) }
        fields.append(("scheduledTime", DriveJSON.escape(stop.scheduledTime)))
        fields.append(("timezone", DriveJSON.escape(stop.timezone)))
        if let facilityCode = stop.facilityCode { fields.append(("facilityCode", DriveJSON.escape(facilityCode))) }
        fields.append(("fullAddress", DriveJSON.escape(stop.fullAddress)))
        fields.append(("city", DriveJSON.escape(stop.city)))
        fields.append(("state", DriveJSON.escape(stop.state)))
        fields.append(("zip", DriveJSON.escape(stop.zip)))
        return object(fields)
    }

    private static func encodePenalty(_ penalty: DrivePenalty) -> String {
        object([
            ("id", String(penalty.id)),
            ("loadId", DriveJSON.escape(penalty.loadId)),
            ("description", DriveJSON.escape(penalty.description)),
            ("amount", String(penalty.amountCents)),
        ])
    }

    private static func encodePaycheck(_ paycheck: DrivePaycheck) -> String {
        var fields: [(String, String)] = [
            ("id", String(paycheck.id)),
            ("weekNumber", String(paycheck.weekNumber)),
            ("year", String(paycheck.year)),
            ("weekLabel", DriveJSON.escape(paycheck.weekLabel)),
            ("weekStartDate", DriveJSON.escape(paycheck.weekStartDate)),
            ("weekEndDate", DriveJSON.escape(paycheck.weekEndDate)),
        ]
        if let driverName = paycheck.driverName { fields.append(("driverName", DriveJSON.escape(driverName))) }
        if let gross = paycheck.grossAmountCents { fields.append(("grossAmount", boxedCents(gross))) }
        fields.append(("netAmount", String(paycheck.netAmountCents)))
        fields.append(("rawExtractedText", DriveJSON.escape(paycheck.rawExtractedText)))
        if let sourceFileName = paycheck.sourceFileName {
            fields.append(("sourceFileName", DriveJSON.escape(sourceFileName)))
        }
        fields.append(("addedAt", String(paycheck.addedAt)))
        if let sourceFilePath = paycheck.sourceFilePath {
            fields.append(("sourceFilePath", DriveJSON.escape(sourceFilePath)))
        }
        return object(fields)
    }

    private static func encodeDiesel(_ fill: DriveDiesel) -> String {
        var fields: [(String, String)] = [
            ("id", String(fill.id)),
            ("weekNumber", String(fill.weekNumber)),
            ("year", String(fill.year)),
            ("weekLabel", DriveJSON.escape(fill.weekLabel)),
            ("weekStartDate", DriveJSON.escape(fill.weekStartDate)),
            ("weekEndDate", DriveJSON.escape(fill.weekEndDate)),
            ("totalAmount", String(fill.totalAmountCents)),
        ]
        if let gallons = fill.gallons { fields.append(("gallons", DriveJSON.renderDouble(gallons))) }
        if let price = fill.pricePerGallonThousandths { fields.append(("pricePerGallon", boxedThousandths(price))) }
        if let discount = fill.discountPricePerGallonThousandths {
            fields.append(("discountPricePerGallon", boxedThousandths(discount)))
        }
        if let location = fill.location { fields.append(("location", DriveJSON.escape(location))) }
        fields.append(("rawExtractedText", DriveJSON.escape(fill.rawExtractedText)))
        if let sourceFileName = fill.sourceFileName {
            fields.append(("sourceFileName", DriveJSON.escape(sourceFileName)))
        }
        fields.append(("addedAt", String(fill.addedAt)))
        return object(fields)
    }

    private static func encodeTask(_ task: DriveMaintenanceTask) -> String {
        var fields: [(String, String)] = [
            ("id", String(task.id)),
            ("title", DriveJSON.escape(task.title)),
            ("startDate", DriveJSON.escape(task.startDate)),
            ("reminderType", DriveJSON.escape(task.reminderType)),
        ]
        if let intervalMiles = task.intervalMiles {
            fields.append(("intervalMiles", DriveJSON.renderDouble(intervalMiles)))
        }
        if let odometer = task.odometerAtStart {
            fields.append(("odometerAtStart", DriveJSON.renderDouble(odometer)))
        }
        if let dueDate = task.dueDate { fields.append(("dueDate", DriveJSON.escape(dueDate))) }
        fields.append(("isCompleted", bool(task.isCompleted)))
        if let completedAt = task.completedAt { fields.append(("completedAt", String(completedAt))) }
        if let notifiedAt = task.notifiedAt { fields.append(("notifiedAt", String(notifiedAt))) }
        fields.append(("createdAt", String(task.createdAt)))
        fields.append(("updatedAt", String(task.updatedAt)))
        return object(fields)
    }

    private static func encodeArchive(_ entry: DriveMaintenanceArchive) -> String {
        var fields: [(String, String)] = [
            ("id", String(entry.id)),
            ("serviceName", DriveJSON.escape(entry.serviceName)),
            ("serviceDate", DriveJSON.escape(entry.serviceDate)),
            ("description", DriveJSON.escape(entry.description)),
            ("amount", DriveJSON.renderDouble(entry.amount)),
        ]
        if let photoPath = entry.photoPath { fields.append(("photoPath", DriveJSON.escape(photoPath))) }
        if let ocrText = entry.ocrText { fields.append(("ocrText", DriveJSON.escape(ocrText))) }
        fields.append(("createdAt", String(entry.createdAt)))
        return object(fields)
    }

    private static func encodeSettings(_ settings: DriveAppSettings) -> String {
        var fields: [(String, String)] = []
        func intField(_ key: String, _ value: Int?) {
            if let value { fields.append((key, String(value))) }
        }
        func boolField(_ key: String, _ value: Bool?) {
            if let value { fields.append((key, bool(value))) }
        }
        func doubleField(_ key: String, _ value: Double?) {
            if let value { fields.append((key, DriveJSON.renderDouble(value))) }
        }
        intField("themeModeOrdinal", settings.themeModeOrdinal)
        intField("languageOrdinal", settings.languageOrdinal)
        boolField("reduceMotion", settings.reduceMotion)
        boolField("oledDark", settings.oledDark)
        boolField("dynamicColor", settings.dynamicColor)
        boolField("parserAutoUpdate", settings.parserAutoUpdate)
        doubleField("parserPriceThresholdPercent", settings.parserPriceThresholdPercent)
        boolField("quietHoursEnabled", settings.quietHoursEnabled)
        intField("quietHoursStart", settings.quietHoursStart)
        intField("quietHoursEnd", settings.quietHoursEnd)
        boolField("notifyMissingWeek", settings.notifyMissingWeek)
        boolField("notifyMaintenance", settings.notifyMaintenance)
        if let lastEquipmentType = settings.lastEquipmentType {
            fields.append(("lastEquipmentType", DriveJSON.escape(lastEquipmentType)))
        }
        doubleField("weeklyProfitGoal", settings.weeklyProfitGoal)
        doubleField("rpmMinProfit", settings.rpmMinProfit)
        doubleField("rpmTargetProfit", settings.rpmTargetProfit)
        // telegramChatId is intentionally never written.
        intField("loadWeekStartDay", settings.loadWeekStartDay)
        intField("dieselWeekStartDay", settings.dieselWeekStartDay)
        return object(fields)
    }

    private static func boxedCents(_ cents: Int64) -> String {
        object([("cents", String(cents))])
    }

    private static func boxedThousandths(_ thousandths: Int64) -> String {
        object([("thousandths", String(thousandths))])
    }

    private static func bool(_ value: Bool) -> String { value ? "true" : "false" }

    private static func object(_ fields: [(String, String)]) -> String {
        var out = "{"
        for (index, field) in fields.enumerated() {
            if index > 0 { out += "," }
            out += DriveJSON.escape(field.0)
            out += ":"
            out += field.1
        }
        out += "}"
        return out
    }

    private static func array(_ values: [String]) -> String {
        "[\(values.joined(separator: ","))]"
    }

    // MARK: - Decode

    private static func array<T>(_ value: Any?, encode: (Any) throws -> T) throws -> [T] {
        if value == nil || value is NSNull { return [] }
        guard let items = value as? [Any] else { throw DriveBackupDecodeError.corrupted }
        return try items.map(encode)
    }

    private static func dictionary(_ value: Any) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else { throw DriveBackupDecodeError.corrupted }
        return dictionary
    }

    private static func load(_ value: Any) throws -> DriveLoad {
        let row = try dictionary(value)
        return DriveLoad(
            id: string(row["id"]) ?? "",
            tripId: string(row["tripId"]) ?? "",
            date: string(row["date"]) ?? "",
            totalRateCents: cents(row["totalRate"]) ?? 0,
            totalMiles: double(row["totalMiles"]) ?? 0,
            pointA: string(row["pointA"]) ?? "",
            pointB: string(row["pointB"]) ?? "",
            puCount: int(row["puCount"]) ?? 0,
            delCount: int(row["delCount"]) ?? 0,
            weekNumber: int(row["weekNumber"]) ?? 0,
            year: int(row["year"]) ?? 0,
            rawMessage: string(row["rawMessage"]) ?? "",
            parsedAt: int64(row["parsedAt"]) ?? 0,
            updatedAt: int64(row["updatedAt"]) ?? 0,
            route: string(row["route"]) ?? "",
            firstPuCityState: string(row["firstPuCityState"]) ?? "",
            lastDelCityState: string(row["lastDelCityState"]) ?? "",
            durationDays: double(row["durationDays"]) ?? 0,
            paceCents: cents(row["pace"]) ?? 0,
            stopCount: int(row["stopCount"]) ?? 0,
            isDispute: boolValue(row["isDispute"]) ?? false,
            disputeResponseDate: string(row["disputeResponseDate"]),
            disputeCompleted: boolValue(row["disputeCompleted"]) ?? false,
            disputeAmountCents: cents(row["disputeAmount"]),
            disputeApplyToLoad: boolValue(row["disputeApplyToLoad"]) ?? false,
            disputeAmountApplied: boolValue(row["disputeAmountApplied"]) ?? false,
            actualFinishDate: string(row["actualFinishDate"]),
            stops: try array(row["stops"], encode: stop),
            penalties: try array(row["penalties"], encode: penalty),
            equipmentType: string(row["equipmentType"]),
            deadheadMiles: double(row["deadheadMiles"]) ?? 0
        )
    }

    private static func stop(_ value: Any) throws -> DriveStop {
        let row = try dictionary(value)
        return DriveStop(
            id: int(row["id"]) ?? 0,
            loadId: string(row["loadId"]) ?? "",
            stopNumber: int(row["stopNumber"]) ?? 0,
            type: string(row["type"]) ?? "PU",
            puNumber: string(row["puNumber"]),
            note: string(row["note"]),
            scheduledTime: string(row["scheduledTime"]) ?? "",
            timezone: string(row["timezone"]) ?? "",
            facilityCode: string(row["facilityCode"]),
            fullAddress: string(row["fullAddress"]) ?? "",
            city: string(row["city"]) ?? "",
            state: string(row["state"]) ?? "",
            zip: string(row["zip"]) ?? ""
        )
    }

    private static func penalty(_ value: Any) throws -> DrivePenalty {
        let row = try dictionary(value)
        return DrivePenalty(
            id: int(row["id"]) ?? 0,
            loadId: string(row["loadId"]) ?? "",
            description: string(row["description"]) ?? "",
            amountCents: cents(row["amount"]) ?? 0
        )
    }

    private static func paycheck(_ value: Any) throws -> DrivePaycheck {
        let row = try dictionary(value)
        return DrivePaycheck(
            id: int(row["id"]) ?? 0,
            weekNumber: int(row["weekNumber"]) ?? 0,
            year: int(row["year"]) ?? 0,
            weekLabel: string(row["weekLabel"]) ?? "",
            weekStartDate: string(row["weekStartDate"]) ?? "",
            weekEndDate: string(row["weekEndDate"]) ?? "",
            driverName: string(row["driverName"]),
            grossAmountCents: cents(row["grossAmount"]),
            netAmountCents: cents(row["netAmount"]) ?? 0,
            rawExtractedText: string(row["rawExtractedText"]) ?? "",
            sourceFileName: string(row["sourceFileName"]),
            addedAt: int64(row["addedAt"]) ?? 0,
            sourceFilePath: string(row["sourceFilePath"])
        )
    }

    private static func diesel(_ value: Any) throws -> DriveDiesel {
        let row = try dictionary(value)
        return DriveDiesel(
            id: int(row["id"]) ?? 0,
            weekNumber: int(row["weekNumber"]) ?? 0,
            year: int(row["year"]) ?? 0,
            weekLabel: string(row["weekLabel"]) ?? "",
            weekStartDate: string(row["weekStartDate"]) ?? "",
            weekEndDate: string(row["weekEndDate"]) ?? "",
            totalAmountCents: cents(row["totalAmount"]) ?? 0,
            gallons: double(row["gallons"]),
            pricePerGallonThousandths: thousandths(row["pricePerGallon"]),
            discountPricePerGallonThousandths: thousandths(row["discountPricePerGallon"]),
            location: string(row["location"]),
            rawExtractedText: string(row["rawExtractedText"]) ?? "",
            sourceFileName: string(row["sourceFileName"]),
            addedAt: int64(row["addedAt"]) ?? 0
        )
    }

    private static func task(_ value: Any) throws -> DriveMaintenanceTask {
        let row = try dictionary(value)
        return DriveMaintenanceTask(
            id: int64(row["id"]) ?? 0,
            title: string(row["title"]) ?? "",
            startDate: string(row["startDate"]) ?? "",
            reminderType: string(row["reminderType"]) ?? "DATE",
            intervalMiles: double(row["intervalMiles"]),
            odometerAtStart: double(row["odometerAtStart"]),
            dueDate: string(row["dueDate"]),
            isCompleted: boolValue(row["isCompleted"]) ?? false,
            completedAt: int64(row["completedAt"]),
            notifiedAt: int64(row["notifiedAt"]),
            createdAt: int64(row["createdAt"]) ?? 0,
            updatedAt: int64(row["updatedAt"]) ?? 0
        )
    }

    private static func archive(_ value: Any) throws -> DriveMaintenanceArchive {
        let row = try dictionary(value)
        return DriveMaintenanceArchive(
            id: int64(row["id"]) ?? 0,
            serviceName: string(row["serviceName"]) ?? "",
            serviceDate: string(row["serviceDate"]) ?? "",
            description: string(row["description"]) ?? "",
            amount: double(row["amount"]) ?? 0,
            photoPath: string(row["photoPath"]),
            ocrText: string(row["ocrText"]),
            createdAt: int64(row["createdAt"]) ?? 0
        )
    }

    private static func settings(_ value: Any) -> DriveAppSettings? {
        guard let row = value as? [String: Any] else { return nil }
        return DriveAppSettings(
            themeModeOrdinal: int(row["themeModeOrdinal"]),
            languageOrdinal: int(row["languageOrdinal"]),
            reduceMotion: boolValue(row["reduceMotion"]),
            oledDark: boolValue(row["oledDark"]),
            dynamicColor: boolValue(row["dynamicColor"]),
            parserAutoUpdate: boolValue(row["parserAutoUpdate"]),
            parserPriceThresholdPercent: double(row["parserPriceThresholdPercent"]),
            quietHoursEnabled: boolValue(row["quietHoursEnabled"]),
            quietHoursStart: int(row["quietHoursStart"]),
            quietHoursEnd: int(row["quietHoursEnd"]),
            notifyMissingWeek: boolValue(row["notifyMissingWeek"]),
            notifyMaintenance: boolValue(row["notifyMaintenance"]),
            lastEquipmentType: string(row["lastEquipmentType"]),
            weeklyProfitGoal: double(row["weeklyProfitGoal"]),
            rpmMinProfit: double(row["rpmMinProfit"]),
            rpmTargetProfit: double(row["rpmTargetProfit"]),
            telegramChatId: int64(row["telegramChatId"]),
            loadWeekStartDay: int(row["loadWeekStartDay"]),
            dieselWeekStartDay: int(row["dieselWeekStartDay"])
        )
    }

    private static func cents(_ value: Any?) -> Int64? {
        if value == nil || value is NSNull { return nil }
        if let number = value as? NSNumber { return number.int64Value }
        if let row = value as? [String: Any] { return int64(row["cents"]) }
        return nil
    }

    private static func thousandths(_ value: Any?) -> Int64? {
        if value == nil || value is NSNull { return nil }
        if let number = value as? NSNumber { return number.int64Value }
        if let row = value as? [String: Any] { return int64(row["thousandths"]) }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if value == nil || value is NSNull { return nil }
        return value as? String
    }

    private static func int(_ value: Any?) -> Int? {
        guard let number = int64(value) else { return nil }
        return Int(number)
    }

    private static func int64(_ value: Any?) -> Int64? {
        if value == nil || value is NSNull { return nil }
        if let number = value as? NSNumber { return number.int64Value }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if value == nil || value is NSNull { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if value == nil || value is NSNull { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }
}
