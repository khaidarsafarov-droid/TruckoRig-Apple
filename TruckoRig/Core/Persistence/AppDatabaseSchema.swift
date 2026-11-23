import Foundation
import GRDB

/// Schema creation and the one-time maintenance import.
extension AppDatabase {
    /// Maps the pre-stage-5 `maintenance` rows into the Android task and archive tables.
    static func copyStubMaintenance(_ db: Database) throws {
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

    static func createSchema(_ db: Database) throws {
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
}
