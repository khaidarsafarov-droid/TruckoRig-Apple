import Foundation
import GRDB

/// Reads one slice of the journal.
extension AppDatabase {
    static func fetchSlice(_ tables: JournalTables, _ db: Database) throws -> StoredGraph {
        let loads = tables.contains(.loads) ? try fetchLoadRows(db) : []
        let photos = tables.contains(.photos) ? try fetchPhotoRows(db) : []
        let scans = tables.contains(.scans) ? try fetchScanRows(db) : []
        if tables.contains(.loads), tables.contains(.photos) {
            attach(photos, to: loads)
        }
        if tables.contains(.loads), tables.contains(.scans) {
            attach(scans, to: loads)
        }
        return StoredGraph(
            loads: loads,
            paychecks: tables.contains(.paychecks) ? try fetchPaychecks(db) : [],
            diesel: tables.contains(.diesel) ? try fetchDiesel(db) : [],
            maintenance: tables.contains(.maintenance) ? try fetchMaintenanceTasks(db) : [],
            maintenanceArchive: tables.contains(.maintenance) ? try fetchMaintenanceArchive(db) : [],
            photos: photos,
            scans: scans,
            profile: tables.contains(.profile) ? try fetchProfile(db) : nil,
            expenses: tables.contains(.expenses) ? try fetchExpenses(db) : [],
            perDiemOverrides: tables.contains(.perDiem) ? try fetchPerDiem(db) : []
        )
    }
}
