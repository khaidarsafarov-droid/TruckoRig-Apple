import Foundation

/// JSON codec and full-replace restore. Gson omits nulls and does not HTML-escape.
public enum BackupDataCodec {
    public static func hasExportableContent(_ backup: BackupData) -> Bool {
        !backup.loads.isEmpty
            || !backup.paychecks.isEmpty
            || !backup.diesel.isEmpty
            || !backup.maintenanceTasks.isEmpty
            || !backup.maintenanceArchive.isEmpty
    }

    public static func carriesMaintenance(_ backup: BackupData) -> Bool {
        BackupSchema.resolve(schemaVersion: backup.schemaVersion, version: backup.version) >= BackupSchema.v2
    }

    public static func encode(_ backup: BackupData) -> String {
        var fields: [(String, String)] = [
            ("schemaVersion", String(BackupSchema.current)),
            ("version", String(BackupSchema.current)),
            ("exportedAt", String(backup.exportedAt)),
        ]
        if let accountId = backup.accountId {
            fields.append(("accountId", BackupJSON.escape(accountId)))
        }
        if let originPlatform = nonEmpty(backup.originPlatform) {
            fields.append(("originPlatform", BackupJSON.escape(originPlatform)))
        }
        if let originDevice = nonEmpty(backup.originDevice) {
            fields.append(("originDevice", BackupJSON.escape(originDevice)))
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

    public static func decode(_ json: String) throws -> BackupData {
        let stripped = BackupJSON.stripBOM(json).trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.isEmpty { throw BackupDecodeError.invalidFormat }
        let root: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: Data(stripped.utf8))
            guard let dictionary = object as? [String: Any] else { throw BackupDecodeError.corrupted }
            root = dictionary
        } catch let error as BackupDecodeError {
            throw error
        } catch {
            throw BackupDecodeError.corrupted
        }
        // The media manifest sits beside this file. It is not a journal and must not restore as one.
        if (root["kind"] as? String) == ICloudMediaPolicy.manifestKind {
            throw BackupDecodeError.invalidFormat
        }
        let schema = BackupSchema.resolve(
            schemaVersion: int(root["schemaVersion"]) ?? 0,
            version: int(root["version"]) ?? 0
        )
        if schema > BackupSchema.current {
            throw BackupDecodeError.schemaTooNew(schema)
        }
        return BackupData(
            schemaVersion: schema,
            version: schema,
            exportedAt: int64(root["exportedAt"]) ?? 0,
            accountId: string(root["accountId"]),
            loads: try array(root["loads"], encode: load),
            paychecks: try array(root["paychecks"], encode: paycheck),
            diesel: try array(root["diesel"], encode: diesel),
            maintenanceTasks: try array(root["maintenanceTasks"], encode: task),
            maintenanceArchive: try array(root["maintenanceArchive"], encode: archive),
            appSettings: root["appSettings"].flatMap { value -> BackupAppSettings? in
                if value is NSNull { return nil }
                return settings(value)
            },
            originDevice: string(root["originDevice"]),
            originPlatform: string(root["originPlatform"])
        )
    }

    public static func fromJSON(_ json: String) -> BackupData? {
        try? decode(json)
    }

    /// Full replace. Schema v1 leaves maintenance in place. Null settings leave the phone's settings.
    public static func restore(
        _ backup: BackupData,
        onto journal: BackupJournal,
        activeAccountId: String,
        allowUnboundAccount: Bool,
        allowForeignAccount: Bool = false
    ) -> BackupRestoreOutcome {
        let account = backup.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let active = activeAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.isEmpty {
            if !allowUnboundAccount { return .rejected(.unboundAccount) }
        } else if !active.isEmpty && account != active && !allowForeignAccount {
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
        byteCount > BackupSchedule.maxRestoreBytes
    }

    // MARK: - Encode

    private static func encodeLoad(_ load: BackupLoad) -> String {
        var fields: [(String, String)] = [
            ("id", BackupJSON.escape(load.id)),
            ("tripId", BackupJSON.escape(load.tripId)),
            ("date", BackupJSON.escape(load.date)),
            ("totalRate", String(load.totalRateCents)),
            ("totalMiles", BackupJSON.renderDouble(load.totalMiles)),
            ("pointA", BackupJSON.escape(load.pointA)),
            ("pointB", BackupJSON.escape(load.pointB)),
            ("puCount", String(load.puCount)),
            ("delCount", String(load.delCount)),
            ("weekNumber", String(load.weekNumber)),
            ("year", String(load.year)),
            ("rawMessage", BackupJSON.escape(load.rawMessage)),
            ("parsedAt", String(load.parsedAt)),
            ("updatedAt", String(load.updatedAt)),
            ("route", BackupJSON.escape(load.route)),
            ("firstPuCityState", BackupJSON.escape(load.firstPuCityState)),
            ("lastDelCityState", BackupJSON.escape(load.lastDelCityState)),
            ("durationDays", BackupJSON.renderDouble(load.durationDays)),
            ("pace", String(load.paceCents)),
            ("stopCount", String(load.stopCount)),
            ("isDispute", bool(load.isDispute)),
        ]
        if let disputeResponseDate = load.disputeResponseDate {
            fields.append(("disputeResponseDate", BackupJSON.escape(disputeResponseDate)))
        }
        fields.append(("disputeCompleted", bool(load.disputeCompleted)))
        if let disputeAmountCents = load.disputeAmountCents {
            fields.append(("disputeAmount", boxedCents(disputeAmountCents)))
        }
        fields.append(("disputeApplyToLoad", bool(load.disputeApplyToLoad)))
        fields.append(("disputeAmountApplied", bool(load.disputeAmountApplied)))
        if let actualFinishDate = load.actualFinishDate {
            fields.append(("actualFinishDate", BackupJSON.escape(actualFinishDate)))
        }
        fields.append(("stops", array(load.stops.map(encodeStop))))
        fields.append(("penalties", array(load.penalties.map(encodePenalty))))
        if let equipmentType = load.equipmentType {
            fields.append(("equipmentType", BackupJSON.escape(equipmentType)))
        }
        fields.append(("deadheadMiles", BackupJSON.renderDouble(load.deadheadMiles)))
        return object(fields)
    }

    private static func encodeStop(_ stop: BackupStop) -> String {
        var fields: [(String, String)] = [
            ("id", String(stop.id)),
            ("loadId", BackupJSON.escape(stop.loadId)),
            ("stopNumber", String(stop.stopNumber)),
            ("type", BackupJSON.escape(stop.type)),
        ]
        if let puNumber = stop.puNumber { fields.append(("puNumber", BackupJSON.escape(puNumber))) }
        if let note = stop.note { fields.append(("note", BackupJSON.escape(note))) }
        fields.append(("scheduledTime", BackupJSON.escape(stop.scheduledTime)))
        fields.append(("timezone", BackupJSON.escape(stop.timezone)))
        if let facilityCode = stop.facilityCode { fields.append(("facilityCode", BackupJSON.escape(facilityCode))) }
        fields.append(("fullAddress", BackupJSON.escape(stop.fullAddress)))
        fields.append(("city", BackupJSON.escape(stop.city)))
        fields.append(("state", BackupJSON.escape(stop.state)))
        fields.append(("zip", BackupJSON.escape(stop.zip)))
        return object(fields)
    }

    private static func encodePenalty(_ penalty: BackupPenalty) -> String {
        object([
            ("id", String(penalty.id)),
            ("loadId", BackupJSON.escape(penalty.loadId)),
            ("description", BackupJSON.escape(penalty.description)),
            ("amount", String(penalty.amountCents)),
        ])
    }

    private static func encodePaycheck(_ paycheck: BackupPaycheck) -> String {
        var fields: [(String, String)] = [
            ("id", String(paycheck.id)),
            ("weekNumber", String(paycheck.weekNumber)),
            ("year", String(paycheck.year)),
            ("weekLabel", BackupJSON.escape(paycheck.weekLabel)),
            ("weekStartDate", BackupJSON.escape(paycheck.weekStartDate)),
            ("weekEndDate", BackupJSON.escape(paycheck.weekEndDate)),
        ]
        if let driverName = paycheck.driverName { fields.append(("driverName", BackupJSON.escape(driverName))) }
        if let gross = paycheck.grossAmountCents { fields.append(("grossAmount", boxedCents(gross))) }
        fields.append(("netAmount", String(paycheck.netAmountCents)))
        fields.append(("rawExtractedText", BackupJSON.escape(paycheck.rawExtractedText)))
        if let sourceFileName = paycheck.sourceFileName {
            fields.append(("sourceFileName", BackupJSON.escape(sourceFileName)))
        }
        fields.append(("addedAt", String(paycheck.addedAt)))
        if let sourceFilePath = paycheck.sourceFilePath {
            fields.append(("sourceFilePath", BackupJSON.escape(sourceFilePath)))
        }
        return object(fields)
    }

    private static func encodeDiesel(_ fill: BackupDiesel) -> String {
        var fields: [(String, String)] = [
            ("id", String(fill.id)),
            ("weekNumber", String(fill.weekNumber)),
            ("year", String(fill.year)),
            ("weekLabel", BackupJSON.escape(fill.weekLabel)),
            ("weekStartDate", BackupJSON.escape(fill.weekStartDate)),
            ("weekEndDate", BackupJSON.escape(fill.weekEndDate)),
            ("totalAmount", String(fill.totalAmountCents)),
        ]
        if let gallons = fill.gallons { fields.append(("gallons", BackupJSON.renderDouble(gallons))) }
        if let price = fill.pricePerGallonThousandths { fields.append(("pricePerGallon", boxedThousandths(price))) }
        if let discount = fill.discountPricePerGallonThousandths {
            fields.append(("discountPricePerGallon", boxedThousandths(discount)))
        }
        if let location = fill.location { fields.append(("location", BackupJSON.escape(location))) }
        fields.append(("rawExtractedText", BackupJSON.escape(fill.rawExtractedText)))
        if let sourceFileName = fill.sourceFileName {
            fields.append(("sourceFileName", BackupJSON.escape(sourceFileName)))
        }
        fields.append(("addedAt", String(fill.addedAt)))
        return object(fields)
    }

    private static func encodeTask(_ task: BackupMaintenanceTask) -> String {
        var fields: [(String, String)] = [
            ("id", String(task.id)),
            ("title", BackupJSON.escape(task.title)),
            ("startDate", BackupJSON.escape(task.startDate)),
            ("reminderType", BackupJSON.escape(task.reminderType)),
        ]
        if let intervalMiles = task.intervalMiles {
            fields.append(("intervalMiles", BackupJSON.renderDouble(intervalMiles)))
        }
        if let odometer = task.odometerAtStart {
            fields.append(("odometerAtStart", BackupJSON.renderDouble(odometer)))
        }
        if let dueDate = task.dueDate { fields.append(("dueDate", BackupJSON.escape(dueDate))) }
        fields.append(("isCompleted", bool(task.isCompleted)))
        if let completedAt = task.completedAt { fields.append(("completedAt", String(completedAt))) }
        if let notifiedAt = task.notifiedAt { fields.append(("notifiedAt", String(notifiedAt))) }
        fields.append(("createdAt", String(task.createdAt)))
        fields.append(("updatedAt", String(task.updatedAt)))
        return object(fields)
    }

    private static func encodeArchive(_ entry: BackupMaintenanceArchive) -> String {
        var fields: [(String, String)] = [
            ("id", String(entry.id)),
            ("serviceName", BackupJSON.escape(entry.serviceName)),
            ("serviceDate", BackupJSON.escape(entry.serviceDate)),
            ("description", BackupJSON.escape(entry.description)),
            ("amount", BackupJSON.renderDouble(entry.amount)),
        ]
        if let photoPath = entry.photoPath { fields.append(("photoPath", BackupJSON.escape(photoPath))) }
        if let ocrText = entry.ocrText { fields.append(("ocrText", BackupJSON.escape(ocrText))) }
        fields.append(("createdAt", String(entry.createdAt)))
        return object(fields)
    }

    private static func encodeSettings(_ settings: BackupAppSettings) -> String {
        var fields: [(String, String)] = []
        func intField(_ key: String, _ value: Int?) {
            if let value { fields.append((key, String(value))) }
        }
        func boolField(_ key: String, _ value: Bool?) {
            if let value { fields.append((key, bool(value))) }
        }
        func doubleField(_ key: String, _ value: Double?) {
            if let value { fields.append((key, BackupJSON.renderDouble(value))) }
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
            fields.append(("lastEquipmentType", BackupJSON.escape(lastEquipmentType)))
        }
        doubleField("weeklyProfitGoal", settings.weeklyProfitGoal)
        doubleField("rpmMinProfit", settings.rpmMinProfit)
        doubleField("rpmTargetProfit", settings.rpmTargetProfit)
        // telegramChatId is intentionally never written.
        intField("loadWeekStartDay", settings.loadWeekStartDay)
        intField("dieselWeekStartDay", settings.dieselWeekStartDay)
        if let distanceUnit = settings.distanceUnit {
            fields.append(("distanceUnit", BackupJSON.escape(distanceUnit)))
        }
        return object(fields)
    }

    private static func boxedCents(_ cents: Int64) -> String {
        object([("cents", String(cents))])
    }

    private static func boxedThousandths(_ thousandths: Int64) -> String {
        object([("thousandths", String(thousandths))])
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func bool(_ value: Bool) -> String { value ? "true" : "false" }

    private static func object(_ fields: [(String, String)]) -> String {
        var out = "{"
        for (index, field) in fields.enumerated() {
            if index > 0 { out += "," }
            out += BackupJSON.escape(field.0)
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
        guard let items = value as? [Any] else { throw BackupDecodeError.corrupted }
        return try items.map(encode)
    }

    private static func dictionary(_ value: Any) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else { throw BackupDecodeError.corrupted }
        return dictionary
    }

    private static func load(_ value: Any) throws -> BackupLoad {
        let row = try dictionary(value)
        return BackupLoad(
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

    private static func stop(_ value: Any) throws -> BackupStop {
        let row = try dictionary(value)
        return BackupStop(
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

    private static func penalty(_ value: Any) throws -> BackupPenalty {
        let row = try dictionary(value)
        return BackupPenalty(
            id: int(row["id"]) ?? 0,
            loadId: string(row["loadId"]) ?? "",
            description: string(row["description"]) ?? "",
            amountCents: cents(row["amount"]) ?? 0
        )
    }

    private static func paycheck(_ value: Any) throws -> BackupPaycheck {
        let row = try dictionary(value)
        return BackupPaycheck(
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

    private static func diesel(_ value: Any) throws -> BackupDiesel {
        let row = try dictionary(value)
        return BackupDiesel(
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

    private static func task(_ value: Any) throws -> BackupMaintenanceTask {
        let row = try dictionary(value)
        return BackupMaintenanceTask(
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

    private static func archive(_ value: Any) throws -> BackupMaintenanceArchive {
        let row = try dictionary(value)
        return BackupMaintenanceArchive(
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

    private static func settings(_ value: Any) -> BackupAppSettings? {
        guard let row = value as? [String: Any] else { return nil }
        return BackupAppSettings(
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
            dieselWeekStartDay: int(row["dieselWeekStartDay"]),
            distanceUnit: string(row["distanceUnit"])
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

enum BackupJSON {
    static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    static func escape(_ raw: String) -> String {
        var out = "\""
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{0008}": out += "\\b"
            case "\u{000C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    /// Java `Double.toString` for the finite values a backup actually stores.
    static func renderDouble(_ value: Double) -> String {
        guard value.isFinite else { return "0.0" }
        let text = String(value)
        if text.contains(".") || text.contains("e") || text.contains("E") { return text }
        return text + ".0"
    }
}
