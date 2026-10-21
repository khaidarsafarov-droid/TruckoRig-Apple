import Foundation

/// One SwiftData journal, read out of the plaintext `TruckoRig_*.store` file.
///
/// SwiftData writes a Core Data SQLite schema: table `ZLOAD`, column `ZTRIPID`, dates as seconds
/// since 2001-01-01, UUIDs as 16-byte blobs. The reader accepts that layout and nothing else, so
/// a half-written file fails the import instead of being guessed at.
struct LegacyJournal {
    var loads: [Load] = []
    var paychecks: [Paycheck] = []
    var diesel: [Diesel] = []
    var maintenance: [MaintenanceTask] = []
    var photos: [Photo] = []
    var scans: [Scan] = []
    var profile: DriverProfile?

    var isEmpty: Bool {
        loads.isEmpty && paychecks.isEmpty && diesel.isEmpty && maintenance.isEmpty
            && photos.isEmpty && scans.isEmpty && profile == nil
    }
}

enum LegacySwiftDataReader {

    static func read(storeURL: URL) throws -> LegacyJournal {
        let connection = try SystemSQLite.open(path: storeURL.path, readOnly: true)
        let tables = try tableNames(connection)
        guard !tables.isEmpty else { return LegacyJournal() }

        var journal = LegacyJournal()
        let loads = try rows(connection, tables: tables, candidates: ["ZLOAD", "Load"])
        var loadsByPK: [Int64: Load] = [:]
        for row in loads {
            guard let load = makeLoad(row) else { continue }
            journal.loads.append(load)
            if let pk = row["Z_PK"]?.int {
                loadsByPK[pk] = load
            }
        }

        for row in try rows(connection, tables: tables, candidates: ["ZSTOP", "Stop"]) {
            guard let load = parent(row, loadsByPK: loadsByPK), let stop = makeStop(row) else { continue }
            stop.load = load
            load.stops = (load.stops ?? []) + [stop]
        }
        for row in try rows(connection, tables: tables, candidates: ["ZPENALTY", "Penalty"]) {
            guard let load = parent(row, loadsByPK: loadsByPK), let penalty = makePenalty(row) else { continue }
            penalty.load = load
            load.penalties = (load.penalties ?? []) + [penalty]
        }
        for row in try rows(connection, tables: tables, candidates: ["ZPHOTO", "Photo"]) {
            guard let photo = makePhoto(row) else { continue }
            if let load = parent(row, loadsByPK: loadsByPK) {
                photo.load = load
                load.photos = (load.photos ?? []) + [photo]
            }
            journal.photos.append(photo)
        }
        for row in try rows(connection, tables: tables, candidates: ["ZSCAN", "Scan"]) {
            guard let scan = makeScan(row) else { continue }
            if let load = parent(row, loadsByPK: loadsByPK) {
                scan.load = load
                load.scans = (load.scans ?? []) + [scan]
            }
            journal.scans.append(scan)
        }

        journal.paychecks = try rows(connection, tables: tables, candidates: ["ZPAYCHECK", "Paycheck"]).compactMap(makePaycheck)
        journal.diesel = try rows(connection, tables: tables, candidates: ["ZDIESEL", "Diesel"]).compactMap(makeDiesel)
        journal.maintenance = try rows(
            connection,
            tables: tables,
            candidates: ["ZMAINTENANCETASK", "MaintenanceTask"]
        ).compactMap(makeMaintenance)
        journal.profile = try rows(
            connection,
            tables: tables,
            candidates: ["ZDRIVERPROFILE", "DriverProfile"]
        ).compactMap(makeProfile).first
        return journal
    }

    // MARK: - Tables

    private static func tableNames(_ connection: SystemSQLite.Connection) throws -> Set<String> {
        let rows = try connection.query("SELECT name FROM sqlite_master WHERE type = 'table'")
        return Set(rows.compactMap { $0["name"]?.text })
    }

    private static func rows(
        _ connection: SystemSQLite.Connection,
        tables: Set<String>,
        candidates: [String]
    ) throws -> [[String: SystemSQLite.Value]] {
        guard let name = candidates.first(where: { candidate in
            tables.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }) else { return [] }
        let actual = tables.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
        guard actual.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
            return []
        }
        return try connection.query("SELECT * FROM \"\(actual)\"")
    }

    private static func parent(_ row: [String: SystemSQLite.Value], loadsByPK: [Int64: Load]) -> Load? {
        guard let pk = field(row, "load")?.int else { return nil }
        return loadsByPK[pk]
    }

    // MARK: - Rows

    private static func makeLoad(_ row: [String: SystemSQLite.Value]) -> Load? {
        guard let id = uuid(field(row, "id")), let trip = text(field(row, "tripId")), !trip.isEmpty else {
            return nil
        }
        let date = self.date(field(row, "date")) ?? self.date(field(row, "parsedAt")) ?? Date(timeIntervalSinceReferenceDate: 0)
        return Load(
            id: id,
            tripId: trip,
            date: date,
            totalRate: double(field(row, "totalRate")) ?? 0,
            totalMiles: double(field(row, "totalMiles")) ?? 0,
            pointA: text(field(row, "pointA")),
            pointB: text(field(row, "pointB")),
            puCount: int(field(row, "puCount")) ?? 0,
            delCount: int(field(row, "delCount")) ?? 0,
            stopCount: int(field(row, "stopCount")) ?? 0,
            weekNumber: int(field(row, "weekNumber")) ?? 0,
            year: int(field(row, "year")) ?? 0,
            rawMessage: text(field(row, "rawMessage")),
            parsedAt: self.date(field(row, "parsedAt")) ?? date,
            updatedAt: self.date(field(row, "updatedAt")) ?? date,
            isDispute: bool(field(row, "isDispute")),
            disputeCompleted: bool(field(row, "disputeCompleted")),
            disputeResponseDate: self.date(field(row, "disputeResponseDate")),
            disputeAmount: double(field(row, "disputeAmount")),
            actualFinishDate: self.date(field(row, "actualFinishDate")),
            firstPickupAt: self.date(field(row, "firstPickupAt")),
            lastDeliveryAt: self.date(field(row, "lastDeliveryAt")),
            durationDays: double(field(row, "durationDays")) ?? 0
        )
    }

    private static func makeStop(_ row: [String: SystemSQLite.Value]) -> Stop? {
        guard let id = uuid(field(row, "id")) else { return nil }
        let rawType = text(field(row, "type")) ?? StopType.pickup.rawValue
        return Stop(
            id: id,
            type: StopType(rawValue: rawType) ?? .pickup,
            stopNumber: int(field(row, "stopNumber")) ?? 0,
            puNumber: text(field(row, "puNumber")),
            note: text(field(row, "note")),
            facility: text(field(row, "facility")),
            fullAddress: text(field(row, "fullAddress")) ?? "",
            city: text(field(row, "city")) ?? "",
            state: text(field(row, "state")) ?? "",
            zip: text(field(row, "zip")),
            scheduledTime: date(field(row, "scheduledTime")),
            scheduledTimeRaw: text(field(row, "scheduledTimeRaw")),
            timezone: text(field(row, "timezone"))
        )
    }

    private static func makePenalty(_ row: [String: SystemSQLite.Value]) -> Penalty? {
        guard let id = uuid(field(row, "id")) else { return nil }
        return Penalty(
            id: id,
            summary: text(field(row, "summary")) ?? "",
            amount: double(field(row, "amount")) ?? 0,
            date: date(field(row, "date")) ?? Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    private static func makePaycheck(_ row: [String: SystemSQLite.Value]) -> Paycheck? {
        guard let id = uuid(field(row, "id")) else { return nil }
        return Paycheck(
            id: id,
            amount: double(field(row, "amount")) ?? 0,
            date: date(field(row, "date")) ?? Date(timeIntervalSinceReferenceDate: 0),
            company: text(field(row, "company")),
            notes: text(field(row, "notes")),
            weekNumber: int(field(row, "weekNumber")) ?? 0,
            year: int(field(row, "year")) ?? 0,
            updatedAt: date(field(row, "updatedAt")) ?? Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    private static func makeDiesel(_ row: [String: SystemSQLite.Value]) -> Diesel? {
        guard let id = uuid(field(row, "id")) else { return nil }
        return Diesel(
            id: id,
            gallons: double(field(row, "gallons")) ?? 0,
            totalCost: double(field(row, "totalCost")) ?? 0,
            pricePerGallon: double(field(row, "pricePerGallon")) ?? 0,
            location: text(field(row, "location")),
            state: text(field(row, "state")),
            date: date(field(row, "date")) ?? Date(timeIntervalSinceReferenceDate: 0),
            odometer: int(field(row, "odometer")),
            updatedAt: date(field(row, "updatedAt")) ?? Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    private static func makeMaintenance(_ row: [String: SystemSQLite.Value]) -> MaintenanceTask? {
        guard let id = uuid(field(row, "id")) else { return nil }
        return MaintenanceTask(
            id: id,
            title: text(field(row, "title")) ?? "",
            dueDate: date(field(row, "dueDate")),
            dueOdometer: int(field(row, "dueOdometer")),
            completedDate: date(field(row, "completedDate")),
            cost: double(field(row, "cost")),
            notes: text(field(row, "notes")),
            isArchived: bool(field(row, "isArchived")),
            updatedAt: date(field(row, "updatedAt")) ?? Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    private static func makePhoto(_ row: [String: SystemSQLite.Value]) -> Photo? {
        guard let id = uuid(field(row, "id")), let fileName = text(field(row, "fileName")), !fileName.isEmpty else {
            return nil
        }
        return Photo(
            id: id,
            fileName: fileName,
            latitude: double(field(row, "latitude")),
            longitude: double(field(row, "longitude")),
            timestamp: date(field(row, "timestamp")) ?? Date(timeIntervalSinceReferenceDate: 0),
            caption: text(field(row, "caption"))
        )
    }

    private static func makeScan(_ row: [String: SystemSQLite.Value]) -> Scan? {
        guard let id = uuid(field(row, "id")), let fileName = text(field(row, "fileName")), !fileName.isEmpty else {
            return nil
        }
        return Scan(
            id: id,
            fileName: fileName,
            ocrText: text(field(row, "ocrText")),
            title: text(field(row, "title")),
            timestamp: date(field(row, "timestamp")) ?? Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    private static func makeProfile(_ row: [String: SystemSQLite.Value]) -> DriverProfile? {
        guard let id = uuid(field(row, "id")) else { return nil }
        let language = text(field(row, "preferredLanguage")).flatMap(AppLanguage.init(rawValue:)) ?? .system
        return DriverProfile(
            id: id,
            name: text(field(row, "name")),
            carrier: text(field(row, "carrier")),
            truckModel: text(field(row, "truckModel")),
            truckYear: int(field(row, "truckYear")),
            licensePlate: text(field(row, "licensePlate")),
            homeState: text(field(row, "homeState")),
            preferredLanguage: language,
            weeklyGoal: double(field(row, "weeklyGoal")) ?? 0,
            updatedAt: date(field(row, "updatedAt")) ?? Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    // MARK: - Values

    /// `tripId` is stored as `ZTRIPID`. A handful of fixtures use the bare property name.
    private static func field(_ row: [String: SystemSQLite.Value], _ property: String) -> SystemSQLite.Value? {
        let prefixed = "Z" + property.uppercased()
        if let key = row.keys.first(where: { $0.caseInsensitiveCompare(prefixed) == .orderedSame }) {
            return row[key]
        }
        if let key = row.keys.first(where: { $0.caseInsensitiveCompare(property) == .orderedSame }) {
            return row[key]
        }
        return nil
    }

    private static func text(_ value: SystemSQLite.Value?) -> String? {
        guard let text = value?.text, !text.isEmpty else { return nil }
        return text
    }

    private static func int(_ value: SystemSQLite.Value?) -> Int? {
        value?.int.map(Int.init)
    }

    private static func double(_ value: SystemSQLite.Value?) -> Double? {
        value?.double
    }

    private static func bool(_ value: SystemSQLite.Value?) -> Bool {
        if let int = value?.int { return int != 0 }
        if let text = value?.text?.lowercased() { return text == "1" || text == "true" }
        return false
    }

    /// SwiftData / Core Data timestamps are seconds since 2001-01-01.
    private static func date(_ value: SystemSQLite.Value?) -> Date? {
        guard let seconds = value?.double else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func uuid(_ value: SystemSQLite.Value?) -> UUID? {
        if let text = value?.text { return UUID(uuidString: text) }
        guard let blob = value?.blob, blob.count == 16 else { return nil }
        let bytes = [UInt8](blob)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
