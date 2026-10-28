import Foundation

/// Rows a file restore writes. Maintenance is replaced only when the backup schema carries it.
struct BackupJournalPlan {
    var loads: [Load]
    var paychecks: [Paycheck]
    var diesel: [Diesel]
    var replaceMaintenance: Bool
    var maintenanceTasks: [MaintenanceTask]
    var maintenanceArchive: [MaintenanceArchiveEntry]
}

/// iOS journal ↔ Android `BackupData`.
///
/// Photos, scans and receipt bytes stay on the phone. The file keeps the path and OCR text
/// Android already stores on a maintenance archive row, and nothing else.
enum BackupJournalMapper {

    static func export(
        graph: AppDatabase.StoredGraph,
        settings: AppSettings,
        identity: BackupIdentityStore,
        accountId: String,
        exportedAt: Int64
    ) -> BackupData {
        var book = identity.load()
        var usedStops = Set<Int>()
        var usedPenalties = Set<Int>()
        var usedPaychecks = Set<Int>()
        var usedDiesel = Set<Int>()
        var usedMaintenance = Set<Int64>()

        let loads = graph.loads.map { load in
            exportLoad(
                load,
                book: &book,
                usedStops: &usedStops,
                usedPenalties: &usedPenalties
            )
        }
        let paychecks = graph.paychecks.map { paycheck in
            exportPaycheck(paycheck, settings: settings, book: &book, used: &usedPaychecks)
        }
        let diesel = graph.diesel.map { fill in
            exportDiesel(fill, settings: settings, book: &book, used: &usedDiesel)
        }
        let tasks = graph.maintenance.map { task in
            exportTask(task, book: &book, used: &usedMaintenance)
        }
        let archive = graph.maintenanceArchive.map { entry in
            exportArchive(entry, book: &book, used: &usedMaintenance)
        }
        adoptStoredThemeIfNeeded(settings, extra: &book.settingsExtra)
        identity.save(book)
        return BackupData(
            schemaVersion: BackupSchema.current,
            version: BackupSchema.current,
            exportedAt: exportedAt,
            accountId: accountId,
            loads: loads,
            paychecks: paychecks,
            diesel: diesel,
            maintenanceTasks: tasks,
            maintenanceArchive: archive,
            appSettings: exportSettings(settings, extra: book.settingsExtra)
        )
    }

    static func importBackup(
        _ backup: BackupData,
        settings: AppSettings,
        identity: BackupIdentityStore,
        now: Date = Date()
    ) -> BackupJournalPlan {
        var book = identity.load()
        let loads = backup.loads.map { importLoad($0, book: &book, now: now) }
        let paychecks = backup.paychecks.map { importPaycheck($0, book: &book, now: now) }
        let diesel = backup.diesel.map { importDiesel($0, book: &book, now: now) }
        let tasks = backup.maintenanceTasks.map { importTask($0, book: &book) }
        let archive = backup.maintenanceArchive.map { importArchive($0, book: &book) }
        if let incoming = backup.appSettings {
            apply(incoming, to: settings, extra: &book.settingsExtra)
        }
        identity.save(book)
        return BackupJournalPlan(
            loads: loads,
            paychecks: paychecks,
            diesel: diesel,
            replaceMaintenance: BackupDataCodec.carriesMaintenance(backup),
            maintenanceTasks: tasks,
            maintenanceArchive: archive
        )
    }

    // MARK: - Loads

    private static func exportLoad(
        _ load: Load,
        book: inout BackupIdentityBook,
        usedStops: inout Set<Int>,
        usedPenalties: inout Set<Int>
    ) -> BackupLoad {
        let androidID = androidLoadID(load.id, book: &book)
        let extra = BackupLoadExtra(
            equipmentType: load.equipmentType,
            deadheadMiles: load.deadheadMiles,
            disputeApplyToLoad: load.disputeApplyToLoad,
            disputeAmountApplied: load.disputeAmountApplied
        )
        book.loadExtras[load.id.uuidString] = extra
        let stops = (load.stops ?? []).sorted { $0.stopNumber < $1.stopNumber }
        let pickups = stops.filter { $0.type == .pickup }
        let deliveries = stops.filter { $0.type == .delivery }
        let first = cityState(pickups.first) ?? load.pointA ?? ""
        let last = cityState(deliveries.last) ?? load.pointB ?? ""
        let route: String
        if !first.isEmpty, !last.isEmpty {
            route = "\(first) → \(last)"
        } else if let pointA = load.pointA, let pointB = load.pointB, !pointA.isEmpty, !pointB.isEmpty {
            route = "\(pointA) → \(pointB)"
        } else {
            route = ""
        }
        let duration = load.durationDays
        let pace: Int64
        if duration > 0 {
            let days = max(1, Int(duration.rounded(.up)))
            pace = MoneyCents.fromDollars(load.totalRate).dividedBy(days).cents
        } else {
            pace = 0
        }
        let driveStops = stops.map { stop in
            exportStop(stop, loadID: androidID, book: &book, used: &usedStops)
        }
        let penalties = (load.penalties ?? []).map { penalty in
            exportPenalty(penalty, loadID: androidID, book: &book, used: &usedPenalties)
        }
        return BackupLoad(
            id: androidID,
            tripId: load.tripId,
            date: DateUtils.isoDay(load.date),
            totalRateCents: MoneyCents.fromDollars(load.totalRate).cents,
            totalMiles: load.totalMiles,
            pointA: first.isEmpty ? (load.pointA ?? "") : first,
            pointB: last.isEmpty ? (load.pointB ?? "") : last,
            puCount: stops.isEmpty ? load.puCount : pickups.count,
            delCount: stops.isEmpty ? load.delCount : deliveries.count,
            weekNumber: load.weekNumber,
            year: load.year,
            rawMessage: load.rawMessage ?? "",
            parsedAt: millis(load.parsedAt),
            updatedAt: millis(load.updatedAt),
            route: route,
            firstPuCityState: first,
            lastDelCityState: last,
            durationDays: duration,
            paceCents: pace,
            stopCount: stops.count,
            isDispute: load.isDispute,
            disputeResponseDate: load.disputeResponseDate.map { DateUtils.isoDay($0) },
            disputeCompleted: load.disputeCompleted,
            disputeAmountCents: load.disputeAmount.map { MoneyCents.fromDollars($0).cents },
            disputeApplyToLoad: extra.disputeApplyToLoad,
            disputeAmountApplied: extra.disputeAmountApplied,
            actualFinishDate: load.actualFinishDate.map(finishString),
            stops: driveStops,
            penalties: penalties,
            equipmentType: extra.equipmentType,
            deadheadMiles: extra.deadheadMiles
        )
    }

    private static func exportStop(
        _ stop: Stop,
        loadID: String,
        book: inout BackupIdentityBook,
        used: inout Set<Int>
    ) -> BackupStop {
        let androidID = BackupIdentity.positiveInt(for: stop.id.uuidString, saved: &book.stopIntByUUID, used: &used)
        return BackupStop(
            id: androidID,
            loadId: loadID,
            stopNumber: stop.stopNumber,
            type: stop.type.rawValue,
            puNumber: blankToNil(stop.puNumber),
            note: blankToNil(stop.note),
            scheduledTime: stop.scheduledTimeRaw ?? "",
            timezone: stop.timezone ?? "",
            facilityCode: blankToNil(stop.facility),
            fullAddress: stop.fullAddress,
            city: stop.city,
            state: stop.state,
            zip: stop.zip ?? ""
        )
    }

    private static func exportPenalty(
        _ penalty: Penalty,
        loadID: String,
        book: inout BackupIdentityBook,
        used: inout Set<Int>
    ) -> BackupPenalty {
        let androidID = BackupIdentity.positiveInt(
            for: penalty.id.uuidString,
            saved: &book.penaltyIntByUUID,
            used: &used
        )
        book.penaltyDates[penalty.id.uuidString] = penalty.date.timeIntervalSince1970
        return BackupPenalty(
            id: androidID,
            loadId: loadID,
            description: penalty.summary,
            amountCents: MoneyCents.fromDollars(penalty.amount).cents
        )
    }

    private static func importLoad(_ load: BackupLoad, book: inout BackupIdentityBook, now: Date) -> Load {
        let id = loadUUID(load.id, book: &book)
        book.loadExtras[id.uuidString] = BackupLoadExtra(
            equipmentType: load.equipmentType,
            deadheadMiles: load.deadheadMiles,
            disputeApplyToLoad: load.disputeApplyToLoad,
            disputeAmountApplied: load.disputeAmountApplied
        )
        let date = noon(load.date) ?? now
        let imported = Load(
            id: id,
            tripId: load.tripId.isEmpty ? load.id : load.tripId,
            date: date,
            totalRate: Double(load.totalRateCents) / 100,
            totalMiles: load.totalMiles,
            pointA: blankToNil(load.pointA),
            pointB: blankToNil(load.pointB),
            puCount: load.puCount,
            delCount: load.delCount,
            stopCount: load.stops.isEmpty ? load.stopCount : load.stops.count,
            weekNumber: load.weekNumber,
            year: load.year,
            rawMessage: blankToNil(load.rawMessage),
            parsedAt: instant(load.parsedAt) ?? date,
            updatedAt: instant(load.updatedAt) ?? date,
            isDispute: load.isDispute,
            disputeCompleted: load.disputeCompleted,
            disputeResponseDate: load.disputeResponseDate.flatMap { noon($0) },
            disputeAmount: load.disputeAmountCents.map { Double($0) / 100 },
            actualFinishDate: load.actualFinishDate.flatMap(parseFinish),
            durationDays: load.durationDays,
            disputeApplyToLoad: load.disputeApplyToLoad,
            disputeAmountApplied: load.disputeAmountApplied,
            equipmentType: load.equipmentType,
            deadheadMiles: load.deadheadMiles
        )
        imported.stops = load.stops.map { importStop($0, loadID: id, book: &book) }
        imported.penalties = load.penalties.map { importPenalty($0, loadID: id, fallback: date, book: &book) }
        return imported
    }

    private static func importStop(_ stop: BackupStop, loadID: UUID, book: inout BackupIdentityBook) -> Stop {
        let key = "\(loadID.uuidString)#\(stop.id)"
        let id: UUID
        if let saved = book.stopUUIDByKey[key], let uuid = UUID(uuidString: saved) {
            id = uuid
        } else {
            id = UUID()
            book.stopUUIDByKey[key] = id.uuidString
        }
        book.stopIntByUUID[id.uuidString] = stop.id
        let imported = Stop(
            id: id,
            type: StopType(rawValue: stop.type) ?? .pickup,
            stopNumber: stop.stopNumber,
            puNumber: stop.puNumber,
            note: stop.note,
            facility: stop.facilityCode,
            fullAddress: stop.fullAddress,
            city: stop.city,
            state: stop.state,
            zip: blankToNil(stop.zip),
            scheduledTimeRaw: blankToNil(stop.scheduledTime),
            timezone: blankToNil(stop.timezone)
        )
        return imported
    }

    private static func importPenalty(
        _ penalty: BackupPenalty,
        loadID: UUID,
        fallback: Date,
        book: inout BackupIdentityBook
    ) -> Penalty {
        let key = "\(loadID.uuidString)#\(penalty.id)"
        let id: UUID
        if let saved = book.penaltyUUIDByKey[key], let uuid = UUID(uuidString: saved) {
            id = uuid
        } else {
            id = UUID()
            book.penaltyUUIDByKey[key] = id.uuidString
        }
        book.penaltyIntByUUID[id.uuidString] = penalty.id
        let date = book.penaltyDates[id.uuidString].map { Date(timeIntervalSince1970: $0) } ?? fallback
        return Penalty(
            id: id,
            summary: penalty.description,
            amount: Double(penalty.amountCents) / 100,
            date: date
        )
    }

    // MARK: - Paychecks and diesel

    private static func exportPaycheck(
        _ paycheck: Paycheck,
        settings: AppSettings,
        book: inout BackupIdentityBook,
        used: inout Set<Int>
    ) -> BackupPaycheck {
        let androidID = BackupIdentity.positiveInt(
            for: paycheck.id.uuidString,
            saved: &book.paycheckIntByUUID,
            used: &used
        )
        var extra = book.paycheckExtras[paycheck.id.uuidString] ?? BackupPaycheckExtra()
        extra.company = paycheck.company
        extra.notes = paycheck.notes
        let range = weekRange(for: paycheck.date, week: settings.truckingWeek)
        let label = extra.weekLabel ?? weekLabel(start: range.start, end: range.end)
        let start = extra.weekStartDate ?? DateUtils.isoDay(range.start)
        let end = extra.weekEndDate ?? DateUtils.isoDay(range.end)
        extra.weekLabel = label
        extra.weekStartDate = start
        extra.weekEndDate = end
        if extra.addedAt == nil { extra.addedAt = millis(paycheck.updatedAt) }
        book.paycheckExtras[paycheck.id.uuidString] = extra
        book.paycheckUUIDByAndroid[String(androidID)] = paycheck.id.uuidString
        return BackupPaycheck(
            id: androidID,
            weekNumber: paycheck.weekNumber,
            year: paycheck.year,
            weekLabel: label,
            weekStartDate: start,
            weekEndDate: end,
            driverName: blankToNil(paycheck.driverName),
            grossAmountCents: paycheck.grossAmount.map { MoneyCents.fromDollars($0).cents },
            netAmountCents: MoneyCents.fromDollars(paycheck.amount).cents,
            rawExtractedText: paycheck.rawText ?? "",
            sourceFileName: blankToNil(paycheck.sourceFileName),
            addedAt: extra.addedAt ?? millis(paycheck.updatedAt),
            sourceFilePath: extra.sourceFilePath
        )
    }

    private static func importPaycheck(_ paycheck: BackupPaycheck, book: inout BackupIdentityBook, now: Date) -> Paycheck {
        let key = String(paycheck.id)
        let id: UUID
        if let saved = book.paycheckUUIDByAndroid[key], let uuid = UUID(uuidString: saved) {
            id = uuid
        } else {
            id = UUID()
            book.paycheckUUIDByAndroid[key] = id.uuidString
        }
        book.paycheckIntByUUID[id.uuidString] = paycheck.id
        var extra = book.paycheckExtras[id.uuidString] ?? BackupPaycheckExtra()
        extra.weekLabel = paycheck.weekLabel
        extra.weekStartDate = paycheck.weekStartDate
        extra.weekEndDate = paycheck.weekEndDate
        extra.sourceFilePath = paycheck.sourceFilePath
        extra.addedAt = paycheck.addedAt
        book.paycheckExtras[id.uuidString] = extra
        let date = noon(paycheck.weekStartDate) ?? instant(paycheck.addedAt) ?? now
        return Paycheck(
            id: id,
            amount: Double(paycheck.netAmountCents) / 100,
            date: date,
            company: extra.company,
            notes: extra.notes,
            weekNumber: paycheck.weekNumber,
            year: paycheck.year,
            grossAmount: paycheck.grossAmountCents.map { Double($0) / 100 },
            driverName: paycheck.driverName,
            rawText: blankToNil(paycheck.rawExtractedText),
            sourceFileName: paycheck.sourceFileName,
            updatedAt: instant(paycheck.addedAt) ?? date
        )
    }

    private static func exportDiesel(
        _ fill: Diesel,
        settings: AppSettings,
        book: inout BackupIdentityBook,
        used: inout Set<Int>
    ) -> BackupDiesel {
        let androidID = BackupIdentity.positiveInt(for: fill.id.uuidString, saved: &book.dieselIntByUUID, used: &used)
        var extra = book.dieselExtras[fill.id.uuidString] ?? BackupDieselExtra()
        extra.state = fill.state
        extra.odometer = fill.odometer
        extra.receiptFileName = fill.receiptFileName
        let range = weekRange(for: fill.date, week: settings.dieselWeek)
        let label = extra.weekLabel ?? weekLabel(start: range.start, end: range.end)
        let start = extra.weekStartDate ?? DateUtils.isoDay(range.start)
        let end = extra.weekEndDate ?? DateUtils.isoDay(range.end)
        extra.weekLabel = label
        extra.weekStartDate = start
        extra.weekEndDate = end
        if extra.addedAt == nil { extra.addedAt = millis(fill.updatedAt) }
        book.dieselExtras[fill.id.uuidString] = extra
        book.dieselUUIDByAndroid[String(androidID)] = fill.id.uuidString
        let price = thousandths(fill.pricePerGallon)
        let discount = fill.discountPricePerGallon.map(thousandths)
        let ref = settings.dieselWeek.week(for: fill.date)
        return BackupDiesel(
            id: androidID,
            weekNumber: ref.weekNumber,
            year: ref.year,
            weekLabel: label,
            weekStartDate: start,
            weekEndDate: end,
            totalAmountCents: MoneyCents.fromDollars(fill.totalCost).cents,
            gallons: fill.gallons,
            pricePerGallonThousandths: price,
            discountPricePerGallonThousandths: discount,
            location: blankToNil(fill.location),
            rawExtractedText: fill.rawText ?? "",
            sourceFileName: blankToNil(fill.sourceFileName),
            addedAt: extra.addedAt ?? millis(fill.updatedAt)
        )
    }

    private static func importDiesel(_ fill: BackupDiesel, book: inout BackupIdentityBook, now: Date) -> Diesel {
        let key = String(fill.id)
        let id: UUID
        if let saved = book.dieselUUIDByAndroid[key], let uuid = UUID(uuidString: saved) {
            id = uuid
        } else {
            id = UUID()
            book.dieselUUIDByAndroid[key] = id.uuidString
        }
        book.dieselIntByUUID[id.uuidString] = fill.id
        var extra = book.dieselExtras[id.uuidString] ?? BackupDieselExtra()
        extra.weekLabel = fill.weekLabel
        extra.weekStartDate = fill.weekStartDate
        extra.weekEndDate = fill.weekEndDate
        extra.addedAt = fill.addedAt
        book.dieselExtras[id.uuidString] = extra
        let date = noon(fill.weekStartDate) ?? instant(fill.addedAt) ?? now
        let price = fill.pricePerGallonThousandths.map { Double($0) / 1000 } ?? 0
        return Diesel(
            id: id,
            gallons: fill.gallons ?? 0,
            totalCost: Double(fill.totalAmountCents) / 100,
            pricePerGallon: price,
            location: fill.location,
            state: extra.state,
            date: date,
            odometer: extra.odometer,
            discountPricePerGallon: fill.discountPricePerGallonThousandths.map { Double($0) / 1000 },
            rawText: blankToNil(fill.rawExtractedText),
            receiptFileName: extra.receiptFileName,
            sourceFileName: fill.sourceFileName,
            updatedAt: instant(fill.addedAt) ?? date
        )
    }

    // MARK: - Maintenance

    private static func exportTask(
        _ task: MaintenanceTask,
        book: inout BackupIdentityBook,
        used: inout Set<Int64>
    ) -> BackupMaintenanceTask {
        let androidID = BackupIdentity.positiveLong(for: task.id, saved: &book.maintenanceLongByID, used: &used)
        book.maintenanceIDByLong[String(androidID)] = task.id
        return BackupMaintenanceTask(
            id: androidID,
            title: task.title,
            startDate: task.startDate,
            reminderType: task.reminderType.rawValue,
            intervalMiles: task.intervalMiles,
            odometerAtStart: task.odometerAtStart,
            dueDate: task.dueDate,
            isCompleted: task.isCompleted,
            completedAt: task.completedAt,
            notifiedAt: task.notifiedAt,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
    }

    private static func importTask(_ task: BackupMaintenanceTask, book: inout BackupIdentityBook) -> MaintenanceTask {
        let id = maintenanceID(task.id, book: &book)
        return MaintenanceTask(
            id: id,
            title: task.title,
            startDate: task.startDate,
            reminderType: MaintenanceReminderType(rawValue: task.reminderType) ?? .date,
            intervalMiles: task.intervalMiles,
            odometerAtStart: task.odometerAtStart,
            dueDate: task.dueDate,
            isCompleted: task.isCompleted,
            completedAt: task.completedAt,
            notifiedAt: task.notifiedAt,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt
        )
    }

    private static func exportArchive(
        _ entry: MaintenanceArchiveEntry,
        book: inout BackupIdentityBook,
        used: inout Set<Int64>
    ) -> BackupMaintenanceArchive {
        let androidID = BackupIdentity.positiveLong(for: entry.id, saved: &book.maintenanceLongByID, used: &used)
        book.maintenanceIDByLong[String(androidID)] = entry.id
        return BackupMaintenanceArchive(
            id: androidID,
            serviceName: entry.serviceName,
            serviceDate: entry.serviceDate,
            description: entry.description,
            amount: Double(entry.amount.cents) / 100,
            photoPath: entry.photoPath,
            ocrText: entry.ocrText,
            createdAt: entry.createdAt
        )
    }

    private static func importArchive(
        _ entry: BackupMaintenanceArchive,
        book: inout BackupIdentityBook
    ) -> MaintenanceArchiveEntry {
        MaintenanceArchiveEntry(
            id: maintenanceID(entry.id, book: &book),
            serviceName: entry.serviceName,
            serviceDate: entry.serviceDate,
            description: entry.description,
            amount: MoneyCents.fromDollars(entry.amount),
            photoPath: entry.photoPath,
            ocrText: entry.ocrText,
            createdAt: entry.createdAt
        )
    }

    // MARK: - Settings

    private static func exportSettings(_ settings: AppSettings, extra: BackupSettingsExtra) -> BackupAppSettings {
        let language: Int?
        switch settings.language {
        case .system:
            language = nil
        case .russian:
            language = 0
        case .english:
            language = 1
        case .spanish:
            language = 2
        case .french:
            language = 3
        }
        let goal = settings.weeklyGoal > 0 ? settings.weeklyGoal : nil
        let week = settings.weekStart.calendarWeekday
        return BackupAppSettings(
            themeModeOrdinal: settings.themeMode.rawValue,
            languageOrdinal: language,
            reduceMotion: settings.reduceMotion,
            oledDark: settings.oledDark,
            dynamicColor: extra.dynamicColor,
            parserAutoUpdate: extra.parserAutoUpdate,
            parserPriceThresholdPercent: extra.parserPriceThresholdPercent,
            quietHoursEnabled: settings.quietHoursEnabled,
            quietHoursStart: settings.quietStartHour,
            quietHoursEnd: settings.quietEndHour,
            notifyMissingWeek: settings.notifyMissingWeek,
            notifyMaintenance: settings.notifyMaintenance,
            lastEquipmentType: extra.lastEquipmentType,
            weeklyProfitGoal: goal,
            rpmMinProfit: settings.rpmMinProfit,
            rpmTargetProfit: settings.rpmTargetProfit,
            loadWeekStartDay: week,
            dieselWeekStartDay: settings.dieselWeekStart.calendarWeekday,
            distanceUnit: settings.explicitMeasurementSystem.map { $0 == .kilometers ? "km" : "mi" }
        )
    }

    /// A backup restored before theme lived in Settings kept the choice only in `extra`.
    static func adoptStoredThemeIfNeeded(_ settings: AppSettings, extra: inout BackupSettingsExtra) {
        if !settings.hasStoredThemeMode, let ordinal = extra.themeModeOrdinal {
            settings.themeMode = AppThemeMode.fromOrdinal(ordinal)
        }
        if !settings.hasStoredOledDark, let oled = extra.oledDark {
            settings.oledDark = oled
        }
    }

    private static func apply(_ incoming: BackupAppSettings, to settings: AppSettings, extra: inout BackupSettingsExtra) {
        if let ordinal = incoming.themeModeOrdinal {
            settings.themeMode = AppThemeMode.fromOrdinal(ordinal)
        }
        extra.themeModeOrdinal = incoming.themeModeOrdinal
        extra.reduceMotion = incoming.reduceMotion
        if let oled = incoming.oledDark {
            settings.oledDark = oled
        }
        extra.oledDark = incoming.oledDark
        extra.dynamicColor = incoming.dynamicColor
        extra.parserAutoUpdate = incoming.parserAutoUpdate
        extra.parserPriceThresholdPercent = incoming.parserPriceThresholdPercent
        extra.lastEquipmentType = incoming.lastEquipmentType
        if let ordinal = incoming.languageOrdinal {
            switch ordinal {
            case 0: settings.language = .russian
            case 1:
                settings.language = .english
                extra.preservedLanguageOrdinal = nil
            case 2:
                settings.language = .spanish
            case 3:
                settings.language = .french
            default:
                break
            }
        }
        if let goal = incoming.weeklyProfitGoal, goal > 0 {
            settings.weeklyGoal = goal
        }
        if let day = incoming.loadWeekStartDay, let start = weekStart(day) {
            settings.weekStart = start
        }
        if let day = incoming.dieselWeekStartDay, let start = weekStart(day) {
            settings.dieselWeekStart = start
        }
        if let reduce = incoming.reduceMotion {
            settings.reduceMotion = reduce
        }
        if let unit = incoming.distanceUnit?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            switch unit {
            case "km": settings.chooseMeasurementSystem(.kilometers)
            case "mi": settings.chooseMeasurementSystem(.miles)
            default: break
            }
        }
        if let quiet = incoming.quietHoursEnabled { settings.quietHoursEnabled = quiet }
        if let start = incoming.quietHoursStart { settings.quietStartHour = start }
        if let end = incoming.quietHoursEnd { settings.quietEndHour = end }
        if let notify = incoming.notifyMissingWeek { settings.notifyMissingWeek = notify }
        if let notify = incoming.notifyMaintenance { settings.notifyMaintenance = notify }
        if let rpm = incoming.rpmMinProfit { settings.rpmMinProfit = rpm }
        if let rpm = incoming.rpmTargetProfit { settings.rpmTargetProfit = rpm }
    }

    // MARK: - Ids and clocks

    private static func androidLoadID(_ id: UUID, book: inout BackupIdentityBook) -> String {
        if let saved = book.loadAndroidByUUID[id.uuidString], !saved.isEmpty {
            return saved
        }
        book.loadAndroidByUUID[id.uuidString] = id.uuidString
        book.loadUUIDByAndroid[id.uuidString] = id.uuidString
        return id.uuidString
    }

    private static func loadUUID(_ androidID: String, book: inout BackupIdentityBook) -> UUID {
        if let saved = book.loadUUIDByAndroid[androidID], let uuid = UUID(uuidString: saved) {
            return uuid
        }
        let uuid = UUID(uuidString: androidID) ?? BackupIdentity.deterministicUUID(androidID)
        book.loadUUIDByAndroid[androidID] = uuid.uuidString
        book.loadAndroidByUUID[uuid.uuidString] = androidID
        return uuid
    }

    private static func maintenanceID(_ androidID: Int64, book: inout BackupIdentityBook) -> String {
        let key = String(androidID)
        if let saved = book.maintenanceIDByLong[key], !saved.isEmpty {
            book.maintenanceLongByID[saved] = androidID
            return saved
        }
        book.maintenanceIDByLong[key] = key
        book.maintenanceLongByID[key] = androidID
        return key
    }

    private static func weekStart(_ calendarDay: Int) -> WeekStartDay? {
        WeekStartDay.allCases.first { $0.calendarWeekday == calendarDay }
    }

    private static func weekRange(for date: Date, week: TruckingWeek) -> (start: Date, end: Date) {
        let ref = week.week(for: date)
        let start = week.startDate(of: ref) ?? date
        let end = week.endDate(of: ref) ?? date
        return (start, end)
    }

    /// Android `getWeekLabelShort`: `24 Feb — 2 Mar`.
    private static func weekLabel(start: Date, end: Date) -> String {
        let calendar = Calendar.current
        func piece(_ date: Date) -> String {
            let day = calendar.component(.day, from: date)
            let month = calendar.component(.month, from: date)
            let symbols = calendar.shortMonthSymbols
            let index = month - 1
            let name = symbols.indices.contains(index) ? symbols[index] : ""
            let cleaned = name.replacingOccurrences(of: ".", with: "").lowercased()
            return "\(day) \(cleaned)"
        }
        return "\(piece(start)) — \(piece(end))"
    }

    private static func cityState(_ stop: Stop?) -> String? {
        guard let stop else { return nil }
        let parts = [stop.city, stop.state].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func thousandths(_ price: Double) -> Int64 {
        guard price.isFinite else { return 0 }
        return Int64((price * 1000).rounded(.toNearestOrAwayFromZero))
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func instant(_ millis: Int64) -> Date? {
        guard millis > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    private static func noon(_ iso: String) -> Date? {
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    private static func finishString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func parseFinish(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for pattern in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: String(raw.prefix(16))) {
                return date
            }
        }
        return noon(raw)
    }

    private static func blankToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
