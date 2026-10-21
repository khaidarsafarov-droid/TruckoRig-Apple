import Foundation
import GRDB

/// Encrypted on-device journal.
///
/// SQLCipher (via the GRDB + SQLCipher package) encrypts the file with a 256-bit passphrase.
/// The passphrase lives in the Keychain, not next to the file. SwiftData could not do this:
/// its store is plaintext SQLite plus Data Protection, which is not the Android SQLCipher model
/// and blocks a locked-device reader.
final class AppDatabase {
    static let legacyImportKey = "swiftDataImport"

    private let queue: DatabaseQueue

    private init(queue: DatabaseQueue) {
        self.queue = queue
    }

    static func open(at url: URL, passphrase: Data) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let queue = try DatabaseQueue(path: url.path, configuration: configuration(passphrase: passphrase))
        let database = AppDatabase(queue: queue)
        try database.migrate()
        return database
    }

    /// In-memory store for previews. Still keyed, so the code path matches the on-disk database.
    static func ephemeral() throws -> AppDatabase {
        let queue = try DatabaseQueue(configuration: configuration(passphrase: Data(repeating: 0x5A, count: 32)))
        let database = AppDatabase(queue: queue)
        try database.migrate()
        return database
    }

    private static func configuration(passphrase: Data) -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let key = Data(passphrase)
        config.prepareDatabase { db in
            try db.usePassphrase(key)
        }
        return config
    }

    /// Folds the write-ahead log into the encrypted file.
    ///
    /// This cannot run inside a transaction: SQLite returns `SQLITE_LOCKED` for
    /// `wal_checkpoint` while one is open, and `DatabaseQueue.write` opens one.
    func checkpoint() throws {
        try queue.inDatabase { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    // MARK: - Schema

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try Self.createSchema(db)
        }
        // Android PhotoEntity / ScanEntity columns that the first schema did not store.
        migrator.registerMigration("v2-media-fields") { db in
            try db.alter(table: "photo") { table in
                table.add(column: "filePath", .text)
                table.add(column: "city", .text).notNull().defaults(to: "")
                table.add(column: "state", .text).notNull().defaults(to: "")
                table.add(column: "zipCode", .text).notNull().defaults(to: "")
            }
            try db.alter(table: "scan") { table in
                table.add(column: "filePath", .text)
                table.add(column: "fileSizeBytes", .integer).notNull().defaults(to: 0)
                table.add(column: "pageCount", .integer).notNull().defaults(to: 1)
                table.add(column: "category", .text).notNull().defaults(to: "OTHER")
            }
        }
        // Android maintenance_tasks / maintenance_archive. The stage-1 stub table is copied once.
        migrator.registerMigration("v3-maintenance") { db in
            try db.create(table: "maintenance_task") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("startDate", .text).notNull()
                table.column("reminderType", .text).notNull()
                table.column("intervalMiles", .double)
                table.column("odometerAtStart", .double)
                table.column("dueDate", .text)
                table.column("isCompleted", .integer).notNull()
                table.column("completedAt", .integer)
                table.column("notifiedAt", .integer)
                table.column("createdAt", .integer).notNull()
                table.column("updatedAt", .integer).notNull()
            }
            try db.create(table: "maintenance_archive") { table in
                table.primaryKey("id", .text)
                table.column("serviceName", .text).notNull().defaults(to: "")
                table.column("serviceDate", .text).notNull()
                table.column("description", .text).notNull()
                table.column("amountCents", .integer).notNull()
                table.column("photoPath", .text)
                table.column("ocrText", .text)
                table.column("createdAt", .integer).notNull()
            }
            try Self.copyStubMaintenance(db)
        }
        migrator.registerMigration("v4_receipts_tax_expenses") { db in
            try db.alter(table: "diesel") { table in
                table.add(column: "discountPricePerGallon", .double)
                table.add(column: "rawText", .text)
                table.add(column: "receiptFileName", .text)
                table.add(column: "sourceFileName", .text)
            }
            try db.alter(table: "paycheck") { table in
                table.add(column: "grossAmount", .double)
                table.add(column: "driverName", .text)
                table.add(column: "rawText", .text)
                table.add(column: "sourceFileName", .text)
            }
            try db.alter(table: "profile") { table in
                table.add(column: "role", .text)
            }
            try db.create(table: "misc_expense") { table in
                table.primaryKey("id", .text)
                table.column("amount", .double).notNull()
                table.column("expenseDescription", .text).notNull()
                table.column("date", .double).notNull()
                table.column("receiptFileName", .text)
                table.column("updatedAt", .double).notNull()
            }
            try db.create(table: "per_diem_override") { table in
                table.primaryKey("isoDate", .text)
                table.column("included", .integer).notNull()
            }
        }
        try migrator.migrate(queue)
    }

    /// Maps the pre-stage-5 `maintenance` rows into the Android task and archive tables.
    private static func copyStubMaintenance(_ db: Database) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM maintenance")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for row in rows {
            guard let id = string(row, "id") else { continue }
            let updated = date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0)
            let due = date(row, "dueDate")
            let completed = date(row, "completedDate")
            let fallback = MaintenanceMileage.isoDay(due ?? completed ?? updated, calendar: calendar)
            let imported = MaintenanceLegacyImport.convert(
                MaintenanceLegacyImport.Stub(
                    id: id,
                    title: string(row, "title") ?? "",
                    dueDateISO: due.map { MaintenanceMileage.isoDay($0, calendar: calendar) },
                    dueOdometer: int(row, "dueOdometer"),
                    completedAtMillis: completed.map { Int64($0.timeIntervalSince1970 * 1000) },
                    cost: double(row, "cost"),
                    notes: string(row, "notes"),
                    updatedAtMillis: Int64(updated.timeIntervalSince1970 * 1000)
                ),
                fallbackStartDate: fallback
            )
            try upsert(db, imported.task)
            if let archive = imported.archive {
                try upsert(db, archive)
            }
        }
    }

    private static func createSchema(_ db: Database) throws {
        try db.create(table: "load") { table in
            table.primaryKey("id", .text)
            table.column("tripId", .text).notNull().unique()
            table.column("date", .double).notNull()
            table.column("totalRate", .double).notNull()
            table.column("totalMiles", .double).notNull()
            table.column("pointA", .text)
            table.column("pointB", .text)
            table.column("puCount", .integer).notNull()
            table.column("delCount", .integer).notNull()
            table.column("stopCount", .integer).notNull()
            table.column("weekNumber", .integer).notNull()
            table.column("year", .integer).notNull()
            table.column("rawMessage", .text)
            table.column("parsedAt", .double).notNull()
            table.column("updatedAt", .double).notNull()
            table.column("isDispute", .integer).notNull()
            table.column("disputeCompleted", .integer).notNull()
            table.column("disputeResponseDate", .double)
            table.column("disputeAmount", .double)
            table.column("actualFinishDate", .double)
            table.column("firstPickupAt", .double)
            table.column("lastDeliveryAt", .double)
            table.column("durationDays", .double).notNull()
        }
        try db.create(index: "load_by_week", on: "load", columns: ["year", "weekNumber"])

        try db.create(table: "stop") { table in
            table.primaryKey("id", .text)
            table.column("loadId", .text).notNull().references("load", column: "id", onDelete: .cascade)
            table.column("type", .text).notNull()
            table.column("stopNumber", .integer).notNull()
            table.column("puNumber", .text)
            table.column("note", .text)
            table.column("facility", .text)
            table.column("fullAddress", .text).notNull()
            table.column("city", .text).notNull()
            table.column("state", .text).notNull()
            table.column("zip", .text)
            table.column("scheduledTime", .double)
            table.column("scheduledTimeRaw", .text)
            table.column("timezone", .text)
        }
        try db.create(index: "stop_by_load", on: "stop", columns: ["loadId"])

        try db.create(table: "penalty") { table in
            table.primaryKey("id", .text)
            table.column("loadId", .text).notNull().references("load", column: "id", onDelete: .cascade)
            table.column("summary", .text).notNull()
            table.column("amount", .double).notNull()
            table.column("date", .double).notNull()
        }

        try db.create(table: "paycheck") { table in
            table.primaryKey("id", .text)
            table.column("amount", .double).notNull()
            table.column("date", .double).notNull()
            table.column("company", .text)
            table.column("notes", .text)
            table.column("weekNumber", .integer).notNull()
            table.column("year", .integer).notNull()
            table.column("updatedAt", .double).notNull()
        }

        try db.create(table: "diesel") { table in
            table.primaryKey("id", .text)
            table.column("gallons", .double).notNull()
            table.column("totalCost", .double).notNull()
            table.column("pricePerGallon", .double).notNull()
            table.column("location", .text)
            table.column("state", .text)
            table.column("date", .double).notNull()
            table.column("odometer", .integer)
            table.column("updatedAt", .double).notNull()
        }

        try db.create(table: "maintenance") { table in
            table.primaryKey("id", .text)
            table.column("title", .text).notNull()
            table.column("dueDate", .double)
            table.column("dueOdometer", .integer)
            table.column("completedDate", .double)
            table.column("cost", .double)
            table.column("notes", .text)
            table.column("isArchived", .integer).notNull()
            table.column("updatedAt", .double).notNull()
        }

        try db.create(table: "photo") { table in
            table.primaryKey("id", .text)
            table.column("loadId", .text).references("load", column: "id", onDelete: .setNull)
            table.column("fileName", .text).notNull()
            table.column("latitude", .double)
            table.column("longitude", .double)
            table.column("timestamp", .double).notNull()
            table.column("caption", .text)
        }

        try db.create(table: "scan") { table in
            table.primaryKey("id", .text)
            table.column("loadId", .text).references("load", column: "id", onDelete: .setNull)
            table.column("fileName", .text).notNull()
            table.column("ocrText", .text)
            table.column("title", .text)
            table.column("timestamp", .double).notNull()
        }

        try db.create(table: "profile") { table in
            table.primaryKey("id", .text)
            table.column("name", .text)
            table.column("carrier", .text)
            table.column("truckModel", .text)
            table.column("truckYear", .integer)
            table.column("licensePlate", .text)
            table.column("homeState", .text)
            table.column("preferredLanguage", .text).notNull()
            table.column("weeklyGoal", .double).notNull()
            table.column("updatedAt", .double).notNull()
        }

        try db.create(table: "meta") { table in
            table.primaryKey("key", .text)
            table.column("value", .text).notNull()
        }
    }

    // MARK: - Reads

    func load(tripId: String) throws -> Load? {
        let normalized = TripID.normalize(tripId)
        return try loads().first { $0.tripId == normalized }
    }

    func loads() throws -> [Load] {
        try fetchGraph().loads
    }

    func fetchGraph() throws -> StoredGraph {
        try queue.read(Self.fetchGraph)
    }

    func legacyImportIsDone() throws -> Bool {
        try queue.read { db in
            let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM meta WHERE key = ?",
                arguments: [Self.legacyImportKey]
            )
            return value == "done"
        }
    }

    // MARK: - Writes

    func save(_ load: Load) throws {
        try queue.write { db in
            try Self.upsert(load, db)
        }
    }

    /// Deletes the load and its photo and scan rows. Files are removed by the caller.
    ///
    /// Android `deletePhotosForLoad` / `deleteScansForLoad` drop the rows and the files together.
    /// Foreign keys would only null the link, which would leave the paperwork behind.
    func delete(_ load: Load) throws -> RemovedMedia {
        try queue.write { db in
            let loadId = load.id.uuidString
            let photos = try Row.fetchAll(
                db,
                sql: "SELECT * FROM photo WHERE loadId = ?",
                arguments: [loadId]
            ).map(Self.photo(from:))
            let scans = try Row.fetchAll(
                db,
                sql: "SELECT * FROM scan WHERE loadId = ?",
                arguments: [loadId]
            ).map(Self.scan(from:))
            try db.execute(sql: "DELETE FROM photo WHERE loadId = ?", arguments: [loadId])
            try db.execute(sql: "DELETE FROM scan WHERE loadId = ?", arguments: [loadId])
            try db.execute(sql: "DELETE FROM load WHERE id = ?", arguments: [loadId])
            return RemovedMedia(photos: photos, scans: scans)
        }
    }

    func save(_ paycheck: Paycheck) throws {
        try queue.write { try Self.upsert($0, paycheck) }
    }

    func delete(_ paycheck: Paycheck) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM paycheck WHERE id = ?", arguments: [paycheck.id.uuidString])
        }
    }

    func save(_ fill: Diesel) throws {
        try queue.write { try Self.upsert($0, fill) }
    }

    func delete(_ fill: Diesel) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM diesel WHERE id = ?", arguments: [fill.id.uuidString])
        }
    }

    func save(_ task: MaintenanceTask) throws {
        try queue.write { try Self.upsert($0, task) }
    }

    func delete(_ task: MaintenanceTask) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM maintenance_task WHERE id = ?", arguments: [task.id])
        }
    }

    func save(_ entry: MaintenanceArchiveEntry) throws {
        try queue.write { try Self.upsert($0, entry) }
    }

    /// Deletes archive rows and returns receipt paths that no remaining row still uses.
    func deleteArchives(ids: [String]) throws -> [String] {
        try queue.write { db in
            let paths = try ids.compactMap { id -> String? in
                try String.fetchOne(
                    db,
                    sql: "SELECT photoPath FROM maintenance_archive WHERE id = ?",
                    arguments: [id]
                )
            }
            for id in ids {
                try db.execute(sql: "DELETE FROM maintenance_archive WHERE id = ?", arguments: [id])
            }
            return try paths.filter { path in
                guard !path.isEmpty else { return false }
                let stillUsed = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM maintenance_archive WHERE photoPath = ?",
                    arguments: [path]
                ) ?? 0
                return stillUsed == 0
            }
        }
    }

    func save(_ photo: Photo) throws {
        try queue.write { try Self.upsert($0, photo) }
    }

    func delete(_ photo: Photo) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM photo WHERE id = ?", arguments: [photo.id.uuidString])
        }
    }

    func save(_ scan: Scan) throws {
        try queue.write { try Self.upsert($0, scan) }
    }

    func delete(_ scan: Scan) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM scan WHERE id = ?", arguments: [scan.id.uuidString])
        }
    }

    func save(_ profile: DriverProfile) throws {
        try queue.write { try Self.upsert($0, profile) }
    }

    func save(_ expense: MiscExpense) throws {
        try queue.write { try Self.upsert($0, expense) }
    }

    func delete(_ expense: MiscExpense) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM misc_expense WHERE id = ?", arguments: [expense.id.uuidString])
        }
    }

    func savePerDiemOverride(isoDate: String, included: Bool) throws {
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO per_diem_override (isoDate, included) VALUES (?, ?)
                ON CONFLICT(isoDate) DO UPDATE SET included = excluded.included
                """,
                arguments: [isoDate, included ? 1 : 0]
            )
        }
    }

    func deletePerDiemOverride(isoDate: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM per_diem_override WHERE isoDate = ?", arguments: [isoDate])
        }
    }

    func markLegacyImportDone() throws {
        try queue.write { db in
            try Self.markLegacyImportDone(db)
        }
    }

    /// Copies a SwiftData journal in one transaction, then records that the copy finished.
    func importLegacy(_ journal: LegacyJournal) throws {
        try queue.write { db in
            for load in journal.loads {
                try Self.upsert(load, db)
            }
            for paycheck in journal.paychecks {
                try Self.upsert(db, paycheck)
            }
            for fill in journal.diesel {
                try Self.upsert(db, fill)
            }
            for task in journal.maintenance {
                try Self.upsert(db, task)
            }
            for entry in journal.maintenanceArchive {
                try Self.upsert(db, entry)
            }
            for photo in journal.photos {
                try Self.upsert(db, photo)
            }
            for scan in journal.scans {
                try Self.upsert(db, scan)
            }
            if let profile = journal.profile {
                try Self.upsert(db, profile)
            }
            try Self.markLegacyImportDone(db)
        }
    }

    private static func markLegacyImportDone(_ db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO meta (key, value) VALUES (?, 'done')
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            arguments: [legacyImportKey]
        )
    }

    // MARK: - Graph

    struct RemovedMedia {
        var photos: [Photo]
        var scans: [Scan]
        var receiptPaths: [String] = []
    }

    struct StoredGraph {
        var loads: [Load]
        var paychecks: [Paycheck]
        var diesel: [Diesel]
        var maintenance: [MaintenanceTask]
        var maintenanceArchive: [MaintenanceArchiveEntry]
        var photos: [Photo]
        var scans: [Scan]
        var profile: DriverProfile?
        var expenses: [MiscExpense]
        var perDiemOverrides: [PerDiemOverride]
    }

    private static func fetchGraph(_ db: Database) throws -> StoredGraph {
        let loadRows = try Row.fetchAll(db, sql: "SELECT * FROM load ORDER BY date DESC")
        let stopRows = try Row.fetchAll(db, sql: "SELECT * FROM stop ORDER BY stopNumber ASC")
        let penaltyRows = try Row.fetchAll(db, sql: "SELECT * FROM penalty ORDER BY date ASC")
        let loads = loadRows.map(load(from:))
        let loadsById = Dictionary(uniqueKeysWithValues: loads.map { ($0.id, $0) })

        for row in stopRows {
            guard let loadId = uuid(row, "loadId"), let load = loadsById[loadId] else { continue }
            let stop = stop(from: row)
            stop.load = load
            load.stops = (load.stops ?? []) + [stop]
        }
        for row in penaltyRows {
            guard let loadId = uuid(row, "loadId"), let load = loadsById[loadId] else { continue }
            let penalty = penalty(from: row)
            penalty.load = load
            load.penalties = (load.penalties ?? []) + [penalty]
        }

        let photos = try Row.fetchAll(db, sql: "SELECT * FROM photo ORDER BY timestamp DESC").map(photo(from:))
        for photo in photos {
            guard let loadId = photo.loadId, let load = loadsById[loadId] else { continue }
            photo.load = load
            load.photos = (load.photos ?? []) + [photo]
        }
        let scans = try Row.fetchAll(db, sql: "SELECT * FROM scan ORDER BY timestamp DESC").map(scan(from:))
        for scan in scans {
            guard let loadId = scan.loadId, let load = loadsById[loadId] else { continue }
            scan.load = load
            load.scans = (load.scans ?? []) + [scan]
        }

        let paychecks = try Row.fetchAll(db, sql: "SELECT * FROM paycheck ORDER BY date DESC").map(paycheck(from:))
        let diesel = try Row.fetchAll(db, sql: "SELECT * FROM diesel ORDER BY date DESC").map(diesel(from:))
        let maintenance = try Row.fetchAll(
            db,
            sql: "SELECT * FROM maintenance_task ORDER BY createdAt ASC"
        ).map(maintenanceTask(from:))
        let archive = try Row.fetchAll(
            db,
            sql: "SELECT * FROM maintenance_archive ORDER BY serviceDate DESC, createdAt DESC"
        ).map(maintenanceArchive(from:))
        let profile = try Row.fetchOne(db, sql: "SELECT * FROM profile LIMIT 1").map(profile(from:))
        let expenses = try Row.fetchAll(db, sql: "SELECT * FROM misc_expense ORDER BY date DESC").map(expense(from:))
        let overrides = try Row.fetchAll(db, sql: "SELECT * FROM per_diem_override ORDER BY isoDate ASC").map(override(from:))
        return StoredGraph(
            loads: loads,
            paychecks: paychecks,
            diesel: diesel,
            maintenance: maintenance,
            maintenanceArchive: archive,
            photos: photos,
            scans: scans,
            profile: profile,
            expenses: expenses,
            perDiemOverrides: overrides
        )
    }

    // MARK: - Upsert

    private static func upsert(_ load: Load, _ db: Database) throws {
        try execute(db, """
        INSERT INTO load (
            id, tripId, date, totalRate, totalMiles, pointA, pointB, puCount, delCount, stopCount,
            weekNumber, year, rawMessage, parsedAt, updatedAt, isDispute, disputeCompleted,
            disputeResponseDate, disputeAmount, actualFinishDate, firstPickupAt, lastDeliveryAt, durationDays
        ) VALUES (\(marks(23)))
        ON CONFLICT(id) DO UPDATE SET
            tripId = excluded.tripId,
            date = excluded.date,
            totalRate = excluded.totalRate,
            totalMiles = excluded.totalMiles,
            pointA = excluded.pointA,
            pointB = excluded.pointB,
            puCount = excluded.puCount,
            delCount = excluded.delCount,
            stopCount = excluded.stopCount,
            weekNumber = excluded.weekNumber,
            year = excluded.year,
            rawMessage = excluded.rawMessage,
            parsedAt = excluded.parsedAt,
            updatedAt = excluded.updatedAt,
            isDispute = excluded.isDispute,
            disputeCompleted = excluded.disputeCompleted,
            disputeResponseDate = excluded.disputeResponseDate,
            disputeAmount = excluded.disputeAmount,
            actualFinishDate = excluded.actualFinishDate,
            firstPickupAt = excluded.firstPickupAt,
            lastDeliveryAt = excluded.lastDeliveryAt,
            durationDays = excluded.durationDays
        """, [
            load.id.uuidString, load.tripId, load.date.timeIntervalSince1970, load.totalRate, load.totalMiles,
            load.pointA, load.pointB, load.puCount, load.delCount, load.stopCount, load.weekNumber, load.year,
            load.rawMessage, load.parsedAt.timeIntervalSince1970, load.updatedAt.timeIntervalSince1970,
            load.isDispute ? 1 : 0, load.disputeCompleted ? 1 : 0,
            load.disputeResponseDate?.timeIntervalSince1970, load.disputeAmount,
            load.actualFinishDate?.timeIntervalSince1970, load.firstPickupAt?.timeIntervalSince1970,
            load.lastDeliveryAt?.timeIntervalSince1970, load.durationDays,
        ])
        try db.execute(sql: "DELETE FROM stop WHERE loadId = ?", arguments: [load.id.uuidString])
        try db.execute(sql: "DELETE FROM penalty WHERE loadId = ?", arguments: [load.id.uuidString])
        for stop in load.stops ?? [] {
            try execute(db, """
            INSERT INTO stop (
                id, loadId, type, stopNumber, puNumber, note, facility, fullAddress, city, state, zip,
                scheduledTime, scheduledTimeRaw, timezone
            ) VALUES (\(marks(14)))
            """, [
                stop.id.uuidString, load.id.uuidString, stop.type.rawValue, stop.stopNumber, stop.puNumber,
                stop.note, stop.facility, stop.fullAddress, stop.city, stop.state, stop.zip,
                stop.scheduledTime?.timeIntervalSince1970, stop.scheduledTimeRaw, stop.timezone,
            ])
        }
        for penalty in load.penalties ?? [] {
            try execute(db, """
            INSERT INTO penalty (id, loadId, summary, amount, date) VALUES (\(marks(5)))
            """, [
                penalty.id.uuidString, load.id.uuidString, penalty.summary, penalty.amount,
                penalty.date.timeIntervalSince1970,
            ])
        }
    }

    private static func upsert(_ db: Database, _ paycheck: Paycheck) throws {
        try execute(db, """
        INSERT INTO paycheck (
            id, amount, date, company, notes, weekNumber, year, updatedAt,
            grossAmount, driverName, rawText, sourceFileName
        )
        VALUES (\(marks(12)))
        ON CONFLICT(id) DO UPDATE SET
            amount = excluded.amount, date = excluded.date, company = excluded.company,
            notes = excluded.notes, weekNumber = excluded.weekNumber, year = excluded.year,
            updatedAt = excluded.updatedAt, grossAmount = excluded.grossAmount,
            driverName = excluded.driverName, rawText = excluded.rawText,
            sourceFileName = excluded.sourceFileName
        """, [
            paycheck.id.uuidString, paycheck.amount, paycheck.date.timeIntervalSince1970, paycheck.company,
            paycheck.notes, paycheck.weekNumber, paycheck.year, paycheck.updatedAt.timeIntervalSince1970,
            paycheck.grossAmount, paycheck.driverName, paycheck.rawText, paycheck.sourceFileName,
        ])
    }

    private static func upsert(_ db: Database, _ fill: Diesel) throws {
        try execute(db, """
        INSERT INTO diesel (
            id, gallons, totalCost, pricePerGallon, location, state, date, odometer, updatedAt,
            discountPricePerGallon, rawText, receiptFileName, sourceFileName
        ) VALUES (\(marks(13)))
        ON CONFLICT(id) DO UPDATE SET
            gallons = excluded.gallons, totalCost = excluded.totalCost, pricePerGallon = excluded.pricePerGallon,
            location = excluded.location, state = excluded.state, date = excluded.date,
            odometer = excluded.odometer, updatedAt = excluded.updatedAt,
            discountPricePerGallon = excluded.discountPricePerGallon, rawText = excluded.rawText,
            receiptFileName = excluded.receiptFileName, sourceFileName = excluded.sourceFileName
        """, [
            fill.id.uuidString, fill.gallons, fill.totalCost, fill.pricePerGallon, fill.location, fill.state,
            fill.date.timeIntervalSince1970, fill.odometer, fill.updatedAt.timeIntervalSince1970,
            fill.discountPricePerGallon, fill.rawText, fill.receiptFileName, fill.sourceFileName,
        ])
    }

    private static func upsert(_ db: Database, _ task: MaintenanceTask) throws {
        try execute(db, """
        INSERT INTO maintenance_task (
            id, title, startDate, reminderType, intervalMiles, odometerAtStart, dueDate,
            isCompleted, completedAt, notifiedAt, createdAt, updatedAt
        ) VALUES (\(marks(12)))
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title, startDate = excluded.startDate, reminderType = excluded.reminderType,
            intervalMiles = excluded.intervalMiles, odometerAtStart = excluded.odometerAtStart,
            dueDate = excluded.dueDate, isCompleted = excluded.isCompleted, completedAt = excluded.completedAt,
            notifiedAt = excluded.notifiedAt, createdAt = excluded.createdAt, updatedAt = excluded.updatedAt
        """, [
            task.id, task.title, task.startDate, task.reminderType.rawValue, task.intervalMiles,
            task.odometerAtStart, task.dueDate, task.isCompleted ? 1 : 0, task.completedAt,
            task.notifiedAt, task.createdAt, task.updatedAt,
        ])
    }

    private static func upsert(_ db: Database, _ entry: MaintenanceArchiveEntry) throws {
        try execute(db, """
        INSERT INTO maintenance_archive (
            id, serviceName, serviceDate, description, amountCents, photoPath, ocrText, createdAt
        ) VALUES (\(marks(8)))
        ON CONFLICT(id) DO UPDATE SET
            serviceName = excluded.serviceName, serviceDate = excluded.serviceDate,
            description = excluded.description, amountCents = excluded.amountCents,
            photoPath = excluded.photoPath, ocrText = excluded.ocrText, createdAt = excluded.createdAt
        """, [
            entry.id, entry.serviceName, entry.serviceDate, entry.description, entry.amount.cents,
            entry.photoPath, entry.ocrText, entry.createdAt,
        ])
    }

    private static func upsert(_ db: Database, _ photo: Photo) throws {
        try execute(db, """
        INSERT INTO photo (
            id, loadId, fileName, filePath, latitude, longitude, city, state, zipCode, timestamp, caption
        ) VALUES (\(marks(11)))
        ON CONFLICT(id) DO UPDATE SET
            loadId = excluded.loadId, fileName = excluded.fileName, filePath = excluded.filePath,
            latitude = excluded.latitude, longitude = excluded.longitude,
            city = excluded.city, state = excluded.state, zipCode = excluded.zipCode,
            timestamp = excluded.timestamp, caption = excluded.caption
        """, [
            photo.id.uuidString, (photo.loadId ?? photo.load?.id)?.uuidString, photo.fileName, photo.filePath,
            photo.latitude, photo.longitude, photo.city, photo.state, photo.zipCode,
            photo.timestamp.timeIntervalSince1970, photo.caption,
        ])
    }

    private static func upsert(_ db: Database, _ scan: Scan) throws {
        try execute(db, """
        INSERT INTO scan (
            id, loadId, fileName, filePath, ocrText, title, timestamp, fileSizeBytes, pageCount, category
        ) VALUES (\(marks(10)))
        ON CONFLICT(id) DO UPDATE SET
            loadId = excluded.loadId, fileName = excluded.fileName, filePath = excluded.filePath,
            ocrText = excluded.ocrText, title = excluded.title, timestamp = excluded.timestamp,
            fileSizeBytes = excluded.fileSizeBytes, pageCount = excluded.pageCount,
            category = excluded.category
        """, [
            scan.id.uuidString, (scan.loadId ?? scan.load?.id)?.uuidString, scan.fileName, scan.filePath,
            scan.ocrText, scan.title, scan.timestamp.timeIntervalSince1970, scan.fileSizeBytes,
            scan.pageCount, scan.category,
        ])
    }

    private static func upsert(_ db: Database, _ profile: DriverProfile) throws {
        try execute(db, """
        INSERT INTO profile (
            id, name, carrier, truckModel, truckYear, licensePlate, homeState, preferredLanguage,
            weeklyGoal, updatedAt, role
        ) VALUES (\(marks(11)))
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name, carrier = excluded.carrier, truckModel = excluded.truckModel,
            truckYear = excluded.truckYear, licensePlate = excluded.licensePlate, homeState = excluded.homeState,
            preferredLanguage = excluded.preferredLanguage, weeklyGoal = excluded.weeklyGoal,
            updatedAt = excluded.updatedAt, role = excluded.role
        """, [
            profile.id.uuidString, profile.name, profile.carrier, profile.truckModel, profile.truckYear,
            profile.licensePlate, profile.homeState, profile.preferredLanguage.rawValue, profile.weeklyGoal,
            profile.updatedAt.timeIntervalSince1970, profile.role,
        ])
    }

    private static func upsert(_ db: Database, _ expense: MiscExpense) throws {
        try execute(db, """
        INSERT INTO misc_expense (id, amount, expenseDescription, date, receiptFileName, updatedAt)
        VALUES (\(marks(6)))
        ON CONFLICT(id) DO UPDATE SET
            amount = excluded.amount, expenseDescription = excluded.expenseDescription,
            date = excluded.date, receiptFileName = excluded.receiptFileName, updatedAt = excluded.updatedAt
        """, [
            expense.id.uuidString, expense.amount, expense.expenseDescription,
            expense.date.timeIntervalSince1970, expense.receiptFileName, expense.updatedAt.timeIntervalSince1970,
        ])
    }

    private static func execute(_ db: Database, _ sql: String, _ values: [(any DatabaseValueConvertible)?]) throws {
        try db.execute(sql: sql, arguments: StatementArguments(values))
    }

    private static func marks(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    // MARK: - Decode

    private static func load(from row: Row) -> Load {
        Load(
            id: uuid(row, "id") ?? UUID(),
            tripId: string(row, "tripId") ?? "",
            date: date(row, "date") ?? Date(timeIntervalSince1970: 0),
            totalRate: double(row, "totalRate") ?? 0,
            totalMiles: double(row, "totalMiles") ?? 0,
            pointA: string(row, "pointA"),
            pointB: string(row, "pointB"),
            puCount: int(row, "puCount") ?? 0,
            delCount: int(row, "delCount") ?? 0,
            stopCount: int(row, "stopCount") ?? 0,
            weekNumber: int(row, "weekNumber") ?? 0,
            year: int(row, "year") ?? 0,
            rawMessage: string(row, "rawMessage"),
            parsedAt: date(row, "parsedAt") ?? Date(timeIntervalSince1970: 0),
            updatedAt: date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0),
            isDispute: bool(row, "isDispute"),
            disputeCompleted: bool(row, "disputeCompleted"),
            disputeResponseDate: date(row, "disputeResponseDate"),
            disputeAmount: double(row, "disputeAmount"),
            actualFinishDate: date(row, "actualFinishDate"),
            firstPickupAt: date(row, "firstPickupAt"),
            lastDeliveryAt: date(row, "lastDeliveryAt"),
            durationDays: double(row, "durationDays") ?? 0
        )
    }

    private static func stop(from row: Row) -> Stop {
        let rawType = string(row, "type") ?? StopType.pickup.rawValue
        return Stop(
            id: uuid(row, "id") ?? UUID(),
            type: StopType(rawValue: rawType) ?? .pickup,
            stopNumber: int(row, "stopNumber") ?? 0,
            puNumber: string(row, "puNumber"),
            note: string(row, "note"),
            facility: string(row, "facility"),
            fullAddress: string(row, "fullAddress") ?? "",
            city: string(row, "city") ?? "",
            state: string(row, "state") ?? "",
            zip: string(row, "zip"),
            scheduledTime: date(row, "scheduledTime"),
            scheduledTimeRaw: string(row, "scheduledTimeRaw"),
            timezone: string(row, "timezone")
        )
    }

    private static func penalty(from row: Row) -> Penalty {
        Penalty(
            id: uuid(row, "id") ?? UUID(),
            summary: string(row, "summary") ?? "",
            amount: double(row, "amount") ?? 0,
            date: date(row, "date") ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func paycheck(from row: Row) -> Paycheck {
        Paycheck(
            id: uuid(row, "id") ?? UUID(),
            amount: double(row, "amount") ?? 0,
            date: date(row, "date") ?? Date(timeIntervalSince1970: 0),
            company: string(row, "company"),
            notes: string(row, "notes"),
            weekNumber: int(row, "weekNumber") ?? 0,
            year: int(row, "year") ?? 0,
            grossAmount: double(row, "grossAmount"),
            driverName: string(row, "driverName"),
            rawText: string(row, "rawText"),
            sourceFileName: string(row, "sourceFileName"),
            updatedAt: date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func diesel(from row: Row) -> Diesel {
        Diesel(
            id: uuid(row, "id") ?? UUID(),
            gallons: double(row, "gallons") ?? 0,
            totalCost: double(row, "totalCost") ?? 0,
            pricePerGallon: double(row, "pricePerGallon") ?? 0,
            location: string(row, "location"),
            state: string(row, "state"),
            date: date(row, "date") ?? Date(timeIntervalSince1970: 0),
            odometer: int(row, "odometer"),
            discountPricePerGallon: double(row, "discountPricePerGallon"),
            rawText: string(row, "rawText"),
            receiptFileName: string(row, "receiptFileName"),
            sourceFileName: string(row, "sourceFileName"),
            updatedAt: date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func maintenanceTask(from row: Row) -> MaintenanceTask {
        let rawType = string(row, "reminderType") ?? MaintenanceReminderType.miles.rawValue
        return MaintenanceTask(
            id: string(row, "id") ?? UUID().uuidString,
            title: string(row, "title") ?? "",
            startDate: string(row, "startDate") ?? "",
            reminderType: MaintenanceReminderType(rawValue: rawType) ?? .miles,
            intervalMiles: double(row, "intervalMiles"),
            odometerAtStart: double(row, "odometerAtStart"),
            dueDate: string(row, "dueDate"),
            isCompleted: bool(row, "isCompleted"),
            completedAt: int64(row, "completedAt"),
            notifiedAt: int64(row, "notifiedAt"),
            createdAt: int64(row, "createdAt") ?? 0,
            updatedAt: int64(row, "updatedAt") ?? 0
        )
    }

    private static func maintenanceArchive(from row: Row) -> MaintenanceArchiveEntry {
        MaintenanceArchiveEntry(
            id: string(row, "id") ?? UUID().uuidString,
            serviceName: string(row, "serviceName") ?? "",
            serviceDate: string(row, "serviceDate") ?? "",
            description: string(row, "description") ?? "",
            amount: MoneyCents(cents: int64(row, "amountCents") ?? 0),
            photoPath: string(row, "photoPath"),
            ocrText: string(row, "ocrText"),
            createdAt: int64(row, "createdAt") ?? 0
        )
    }

    private static func photo(from row: Row) -> Photo {
        let photo = Photo(
            id: uuid(row, "id") ?? UUID(),
            fileName: string(row, "fileName") ?? "",
            filePath: string(row, "filePath"),
            latitude: double(row, "latitude"),
            longitude: double(row, "longitude"),
            city: string(row, "city") ?? "",
            state: string(row, "state") ?? "",
            zipCode: string(row, "zipCode") ?? "",
            timestamp: date(row, "timestamp") ?? Date(timeIntervalSince1970: 0),
            caption: string(row, "caption")
        )
        photo.loadId = uuid(row, "loadId")
        return photo
    }

    private static func scan(from row: Row) -> Scan {
        let scan = Scan(
            id: uuid(row, "id") ?? UUID(),
            fileName: string(row, "fileName") ?? "",
            filePath: string(row, "filePath"),
            ocrText: string(row, "ocrText"),
            title: string(row, "title"),
            timestamp: date(row, "timestamp") ?? Date(timeIntervalSince1970: 0),
            fileSizeBytes: int64(row, "fileSizeBytes") ?? 0,
            pageCount: int(row, "pageCount") ?? 1,
            category: string(row, "category") ?? ScanDocumentCategory.other.rawValue
        )
        scan.loadId = uuid(row, "loadId")
        return scan
    }

    private static func profile(from row: Row) -> DriverProfile {
        let rawLanguage = string(row, "preferredLanguage") ?? AppLanguage.system.rawValue
        return DriverProfile(
            id: uuid(row, "id") ?? UUID(),
            name: string(row, "name"),
            carrier: string(row, "carrier"),
            truckModel: string(row, "truckModel"),
            truckYear: int(row, "truckYear"),
            licensePlate: string(row, "licensePlate"),
            homeState: string(row, "homeState"),
            role: string(row, "role"),
            preferredLanguage: AppLanguage(rawValue: rawLanguage) ?? .system,
            weeklyGoal: double(row, "weeklyGoal") ?? 0,
            updatedAt: date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func expense(from row: Row) -> MiscExpense {
        MiscExpense(
            id: uuid(row, "id") ?? UUID(),
            amount: double(row, "amount") ?? 0,
            expenseDescription: string(row, "expenseDescription") ?? "",
            date: date(row, "date") ?? Date(timeIntervalSince1970: 0),
            receiptFileName: string(row, "receiptFileName"),
            updatedAt: date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func override(from row: Row) -> PerDiemOverride {
        PerDiemOverride(isoDate: string(row, "isoDate") ?? "", included: bool(row, "included"))
    }

    private static func string(_ row: Row, _ column: String) -> String? { row[column] }
    private static func double(_ row: Row, _ column: String) -> Double? { row[column] }
    private static func int(_ row: Row, _ column: String) -> Int? { row[column] }
    private static func int64(_ row: Row, _ column: String) -> Int64? { row[column] }

    private static func uuid(_ row: Row, _ column: String) -> UUID? {
        string(row, column).flatMap(UUID.init(uuidString:))
    }

    private static func date(_ row: Row, _ column: String) -> Date? {
        double(row, column).map { Date(timeIntervalSince1970: $0) }
    }

    private static func bool(_ row: Row, _ column: String) -> Bool {
        (int(row, column) ?? 0) != 0
    }
}
