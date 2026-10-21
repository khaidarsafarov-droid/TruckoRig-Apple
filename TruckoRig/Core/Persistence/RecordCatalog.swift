import Foundation
import Observation

/// In-memory copy of the encrypted journal for SwiftUI.
///
/// Screens used to subscribe with `@Query`. They now read this catalog, which is reloaded after
/// every successful write.
@MainActor
@Observable
final class RecordCatalog {
    private(set) var loads: [Load] = []
    private(set) var paychecks: [Paycheck] = []
    private(set) var diesel: [Diesel] = []
    private(set) var maintenance: [MaintenanceTask] = []
    private(set) var maintenanceArchive: [MaintenanceArchiveEntry] = []
    private(set) var photos: [Photo] = []
    private(set) var scans: [Scan] = []
    private(set) var profile: DriverProfile?

    func reload(from database: AppDatabase) {
        do {
            let graph = try database.fetchGraph()
            loads = graph.loads
            paychecks = graph.paychecks
            diesel = graph.diesel
            maintenance = graph.maintenance
            maintenanceArchive = graph.maintenanceArchive
            photos = graph.photos
            scans = graph.scans
            profile = graph.profile
        } catch {
            AppLog.persistence.error("Could not reload the journal: \(error.localizedDescription, privacy: .public)")
        }
    }
}
