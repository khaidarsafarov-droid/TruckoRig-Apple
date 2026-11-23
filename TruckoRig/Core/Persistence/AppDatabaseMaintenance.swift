import Foundation
import GRDB

/// Maintenance task and archive rows.
extension AppDatabase {
    static func fetchMaintenanceTasks(_ db: Database) throws -> [MaintenanceTask] {
        try Row.fetchAll(db, sql: "SELECT * FROM maintenance_task ORDER BY createdAt ASC").map(maintenanceTask(from:))
    }


    static func fetchMaintenanceArchive(_ db: Database) throws -> [MaintenanceArchiveEntry] {
        try Row.fetchAll(
            db,
            sql: "SELECT * FROM maintenance_archive ORDER BY serviceDate DESC, createdAt DESC"
        ).map(maintenanceArchive(from:))
    }


    static func upsert(_ db: Database, _ task: MaintenanceTask) throws {
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


    static func upsert(_ db: Database, _ entry: MaintenanceArchiveEntry) throws {
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


    static func maintenanceTask(from row: Row) -> MaintenanceTask {
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


    static func maintenanceArchive(from row: Row) -> MaintenanceArchiveEntry {
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
}
