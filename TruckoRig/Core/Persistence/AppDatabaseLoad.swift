import Foundation
import GRDB

/// Load, stop, and penalty rows.
extension AppDatabase {
    static func fetchLoadRows(_ db: Database) throws -> [Load] {
        let loads = try Row.fetchAll(db, sql: "SELECT * FROM load ORDER BY date DESC").map(load(from:))
        let loadsById = Dictionary(uniqueKeysWithValues: loads.map { ($0.id, $0) })
        let stopRows = try Row.fetchAll(db, sql: "SELECT * FROM stop ORDER BY stopNumber ASC")
        for row in stopRows {
            guard let loadId = uuid(row, "loadId"), let load = loadsById[loadId] else { continue }
            let stop = stop(from: row)
            stop.load = load
            load.stops = (load.stops ?? []) + [stop]
        }
        let penaltyRows = try Row.fetchAll(db, sql: "SELECT * FROM penalty ORDER BY date ASC")
        for row in penaltyRows {
            guard let loadId = uuid(row, "loadId"), let load = loadsById[loadId] else { continue }
            let penalty = penalty(from: row)
            penalty.load = load
            load.penalties = (load.penalties ?? []) + [penalty]
        }
        return loads
    }


    static func upsert(_ load: Load, _ db: Database) throws {
        try execute(db, """
        INSERT INTO load (
            id, tripId, date, totalRate, totalMiles, pointA, pointB, puCount, delCount, stopCount,
            weekNumber, year, rawMessage, parsedAt, updatedAt, isDispute, disputeCompleted,
            disputeResponseDate, disputeAmount, actualFinishDate, firstPickupAt, lastDeliveryAt, durationDays,
            disputeApplyToLoad, disputeAmountApplied, equipmentType, deadheadMiles
        ) VALUES (\(marks(27)))
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
            durationDays = excluded.durationDays,
            disputeApplyToLoad = excluded.disputeApplyToLoad,
            disputeAmountApplied = excluded.disputeAmountApplied,
            equipmentType = excluded.equipmentType,
            deadheadMiles = excluded.deadheadMiles
        """, [
            load.id.uuidString, load.tripId, load.date.timeIntervalSince1970, load.totalRate, load.totalMiles,
            load.pointA, load.pointB, load.puCount, load.delCount, load.stopCount, load.weekNumber, load.year,
            load.rawMessage, load.parsedAt.timeIntervalSince1970, load.updatedAt.timeIntervalSince1970,
            load.isDispute ? 1 : 0, load.disputeCompleted ? 1 : 0,
            load.disputeResponseDate?.timeIntervalSince1970, load.disputeAmount,
            load.actualFinishDate?.timeIntervalSince1970, load.firstPickupAt?.timeIntervalSince1970,
            load.lastDeliveryAt?.timeIntervalSince1970, load.durationDays,
            load.disputeApplyToLoad ? 1 : 0, load.disputeAmountApplied ? 1 : 0,
            load.equipmentType, load.deadheadMiles,
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


    /// Attaches only the children of this load. Other tables stay unread.
    static func assemble(load row: Row, _ db: Database) throws -> Load {
        let load = load(from: row)
        let loadId = load.id.uuidString
        let stops = try Row.fetchAll(
            db,
            sql: "SELECT * FROM stop WHERE loadId = ? ORDER BY stopNumber ASC",
            arguments: [loadId]
        ).map(stop(from:))
        if !stops.isEmpty {
            for stop in stops { stop.load = load }
            load.stops = stops
        }
        let penalties = try Row.fetchAll(
            db,
            sql: "SELECT * FROM penalty WHERE loadId = ? ORDER BY date ASC",
            arguments: [loadId]
        ).map(penalty(from:))
        if !penalties.isEmpty {
            for penalty in penalties { penalty.load = load }
            load.penalties = penalties
        }
        let photos = try Row.fetchAll(
            db,
            sql: "SELECT * FROM photo WHERE loadId = ? ORDER BY timestamp DESC",
            arguments: [loadId]
        ).map(photo(from:))
        if !photos.isEmpty {
            for photo in photos { photo.load = load }
            load.photos = photos
        }
        let scans = try Row.fetchAll(
            db,
            sql: "SELECT * FROM scan WHERE loadId = ? ORDER BY timestamp DESC",
            arguments: [loadId]
        ).map(scan(from:))
        if !scans.isEmpty {
            for scan in scans { scan.load = load }
            load.scans = scans
        }
        return load
    }


    static func load(from row: Row) -> Load {
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
            disputeApplyToLoad: bool(row, "disputeApplyToLoad"),
            disputeAmountApplied: bool(row, "disputeAmountApplied"),
            equipmentType: string(row, "equipmentType"),
            deadheadMiles: double(row, "deadheadMiles") ?? 0,
            actualFinishDate: date(row, "actualFinishDate"),
            firstPickupAt: date(row, "firstPickupAt"),
            lastDeliveryAt: date(row, "lastDeliveryAt"),
            durationDays: double(row, "durationDays") ?? 0
        )
    }


    static func stop(from row: Row) -> Stop {
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


    static func penalty(from row: Row) -> Penalty {
        Penalty(
            id: uuid(row, "id") ?? UUID(),
            summary: string(row, "summary") ?? "",
            amount: double(row, "amount") ?? 0,
            date: date(row, "date") ?? Date(timeIntervalSince1970: 0)
        )
    }
}
