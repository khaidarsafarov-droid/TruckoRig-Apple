import Foundation
import GRDB

/// Tables a journal write can invalidate. A reload reads these and leaves the rest alone.
struct JournalTables: OptionSet, Sendable, Equatable {
    let rawValue: UInt

    static let loads = JournalTables(rawValue: 1 << 0)
    static let paychecks = JournalTables(rawValue: 1 << 1)
    static let diesel = JournalTables(rawValue: 1 << 2)
    static let maintenance = JournalTables(rawValue: 1 << 3)
    static let photos = JournalTables(rawValue: 1 << 4)
    static let scans = JournalTables(rawValue: 1 << 5)
    static let profile = JournalTables(rawValue: 1 << 6)
    static let expenses = JournalTables(rawValue: 1 << 7)
    static let perDiem = JournalTables(rawValue: 1 << 8)

    static let all: JournalTables = [
        .loads, .paychecks, .diesel, .maintenance, .photos, .scans, .profile, .expenses, .perDiem,
    ]
}

/// Coalesces save notifications so an import reloads the journal once.
final class JournalSaveNotifier {
    var deliver: ((JournalTables) -> Void)?
    private var depth = 0
    private var pending: JournalTables = []

    init(deliver: ((JournalTables) -> Void)? = nil) {
        self.deliver = deliver
    }

    func saved(_ tables: JournalTables) {
        guard !tables.isEmpty else { return }
        if depth > 0 {
            pending.formUnion(tables)
        } else {
            deliver?(tables)
        }
    }

    func batch(_ work: () throws -> Void) rethrows {
        depth += 1
        defer {
            depth -= 1
            guard depth == 0 else { return }
            let tables = pending
            pending = []
            if !tables.isEmpty { deliver?(tables) }
        }
        try work()
    }
}

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
        migrator.registerMigration("v5_load_profile_parity") { db in
            try db.alter(table: "load") { table in
                table.add(column: "disputeApplyToLoad", .integer).notNull().defaults(to: 0)
                table.add(column: "disputeAmountApplied", .integer).notNull().defaults(to: 0)
                table.add(column: "equipmentType", .text)
                table.add(column: "deadheadMiles", .double).notNull().defaults(to: 0)
            }
            try db.alter(table: "profile") { table in
                table.add(column: "cdlNumber", .text)
                table.add(column: "experienceYears", .integer)
                table.add(column: "phoneNumber", .text)
                table.add(column: "telegramUsername", .text)
                table.add(column: "avatarFileName", .text)
            }
        }
        migrator.registerMigration("v6_profile_name_only") { db in
            // Copy the columns the app still uses, then drop the old table. Existing names and
            // truck fields stay. Role, carrier, CDL, experience, phone, Telegram and the photo
            // file name are left behind.
            try db.execute(sql: """
                CREATE TABLE profile_name_only (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT,
                    truckModel TEXT,
                    truckYear INTEGER,
                    licensePlate TEXT,
                    homeState TEXT,
                    preferredLanguage TEXT NOT NULL,
                    weeklyGoal DOUBLE NOT NULL,
                    updatedAt DOUBLE NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO profile_name_only (
                    id, name, truckModel, truckYear, licensePlate, homeState,
                    preferredLanguage, weeklyGoal, updatedAt
                )
                SELECT
                    id, name, truckModel, truckYear, licensePlate, homeState,
                    preferredLanguage, weeklyGoal, updatedAt
                FROM profile
                """)
            try db.execute(sql: "DROP TABLE profile")
            try db.execute(sql: "ALTER TABLE profile_name_only RENAME TO profile")
        }
        try migrator.migrate(queue)
    }

    // MARK: - Reads

    /// One trip, by its natural key. Stops, penalties, photos, and scans for that row only.
    ///
    /// The duplicate check before an insert uses this. It must not read the rest of the journal.
    func load(tripId: String) throws -> Load? {
        let normalized = TripID.normalize(tripId)
        return try queue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM load WHERE tripId = ?",
                arguments: [normalized]
            ) else { return nil }
            return try Self.assemble(load: row, db)
        }
    }

    func loads() throws -> [Load] {
        try fetchSlice(.loads).loads
    }

    struct TableCounts: Equatable {
        var loads = 0
        var paychecks = 0
        var diesel = 0
        var maintenance = 0
        var maintenanceArchive = 0
        var photos = 0
        var scans = 0
        var profiles = 0

        func matches(_ journal: LegacyJournal) -> Bool {
            loads == journal.loads.count
                && paychecks == journal.paychecks.count
                && diesel == journal.diesel.count
                && maintenance == journal.maintenance.count
                && maintenanceArchive == journal.maintenanceArchive.count
                && photos == journal.photos.count
                && scans == journal.scans.count
                && profiles == (journal.profile == nil ? 0 : 1)
        }
    }

    func tableCounts() throws -> TableCounts {
        try queue.read { db in
            func count(_ table: String) throws -> Int {
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
            }
            return TableCounts(
                loads: try count("load"),
                paychecks: try count("paycheck"),
                diesel: try count("diesel"),
                maintenance: try count("maintenance_task"),
                maintenanceArchive: try count("maintenance_archive"),
                photos: try count("photo"),
                scans: try count("scan"),
                profiles: try count("profile")
            )
        }
    }

    func fetchSlice(_ tables: JournalTables) throws -> StoredGraph {
        try queue.read { db in
            try Self.fetchSlice(tables, db)
        }
    }

    func fetchGraph() throws -> StoredGraph {
        try fetchSlice(.all)
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

    /// Full replace of loads, paychecks and diesel. Maintenance is replaced only for schema v2.
    ///
    /// Photos and scans linked to a load that is not in the backup are deleted. Unlinked media
    /// stays. Receipt files are not deleted here; the caller removes the returned photo and scan files.
    /// Loads are upserted rather than deleted first, so a kept load does not lose its photos.
    func applyBackupJournal(_ plan: BackupJournalPlan) throws -> RemovedMedia {
        try queue.write { db in
            let kept = plan.loads.map(\.id.uuidString)
            let removedPhotos = try Self.mediaRows(db, table: "photo", kept: kept).map(Self.photo(from:))
            let removedScans = try Self.mediaRows(db, table: "scan", kept: kept).map(Self.scan(from:))
            try Self.deleteMedia(db, table: "photo", kept: kept)
            try Self.deleteMedia(db, table: "scan", kept: kept)

            for load in plan.loads {
                try db.execute(
                    sql: "UPDATE load SET tripId = ? WHERE id = ?",
                    arguments: ["__backup_\(load.id.uuidString)", load.id.uuidString]
                )
            }
            if kept.isEmpty {
                try db.execute(sql: "DELETE FROM load")
            } else {
                let marks = Array(repeating: "?", count: kept.count).joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM load WHERE id NOT IN (\(marks))",
                    arguments: StatementArguments(kept.map { $0 as (any DatabaseValueConvertible)? })
                )
            }
            for load in plan.loads {
                try db.execute(
                    sql: "DELETE FROM load WHERE tripId = ? AND id <> ?",
                    arguments: [load.tripId, load.id.uuidString]
                )
            }
            for load in plan.loads {
                try Self.upsert(load, db)
            }

            try db.execute(sql: "DELETE FROM paycheck")
            for paycheck in plan.paychecks {
                try Self.upsert(db, paycheck)
            }
            try db.execute(sql: "DELETE FROM diesel")
            for fill in plan.diesel {
                try Self.upsert(db, fill)
            }
            if plan.replaceMaintenance {
                try db.execute(sql: "DELETE FROM maintenance_task")
                try db.execute(sql: "DELETE FROM maintenance_archive")
                for task in plan.maintenanceTasks {
                    try Self.upsert(db, task)
                }
                for entry in plan.maintenanceArchive {
                    try Self.upsert(db, entry)
                }
            }
            return RemovedMedia(photos: removedPhotos, scans: removedScans)
        }
    }

    private static func mediaRows(_ db: Database, table: String, kept: [String]) throws -> [Row] {
        if kept.isEmpty {
            return try Row.fetchAll(db, sql: "SELECT * FROM \(table) WHERE loadId IS NOT NULL AND loadId != ''")
        }
        let marks = Array(repeating: "?", count: kept.count).joined(separator: ",")
        return try Row.fetchAll(
            db,
            sql: "SELECT * FROM \(table) WHERE loadId IS NOT NULL AND loadId != '' AND loadId NOT IN (\(marks))",
            arguments: StatementArguments(kept.map { $0 as (any DatabaseValueConvertible)? })
        )
    }

    private static func deleteMedia(_ db: Database, table: String, kept: [String]) throws {
        if kept.isEmpty {
            try db.execute(sql: "DELETE FROM \(table) WHERE loadId IS NOT NULL AND loadId != ''")
            return
        }
        let marks = Array(repeating: "?", count: kept.count).joined(separator: ",")
        try db.execute(
            sql: "DELETE FROM \(table) WHERE loadId IS NOT NULL AND loadId != '' AND loadId NOT IN (\(marks))",
            arguments: StatementArguments(kept.map { $0 as (any DatabaseValueConvertible)? })
        )
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

    /// Copies a SwiftData journal in one transaction. The caller marks the import done
    /// only after the row counts match, so a mismatch can be tried again.
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

}
