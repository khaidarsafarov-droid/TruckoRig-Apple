import Foundation
import Observation

/// In-memory copy of the encrypted journal for SwiftUI.
///
/// Screens read this catalog. A write reloads only the tables it changed, and the SQL runs off
/// the main actor. Arrays stay as they were until that read finishes, so a slow save does not
/// blank the journal.
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
    private(set) var expenses: [MiscExpense] = []
    private(set) var perDiemOverrides: [PerDiemOverride] = []

    @ObservationIgnored private var generation = 0
    /// Set when a reload cannot read the database. The previous arrays stay on screen.
    @ObservationIgnored var onReadFailure: ((String) -> Void)?

    /// Reads `tables` on a background queue, then publishes them on the main actor.
    func reload(
        _ tables: JournalTables = .all,
        from database: AppDatabase,
        completion: (@MainActor () -> Void)? = nil
    ) {
        generation += 1
        let token = generation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let graph = try database.fetchSlice(tables)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.generation == token else { return }
                        self.apply(graph, tables: tables)
                        completion?()
                    }
                }
            } catch {
                let description = error.localizedDescription
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.generation == token else { return }
                        AppLog.persistence.error("Could not reload the journal: \(description, privacy: .public)")
                        self.onReadFailure?(description)
                    }
                }
            }
        }
    }

    /// Same read, waited on. Used while the first catalog is built, before the window is shown.
    func reloadNow(_ tables: JournalTables = .all, from database: AppDatabase) {
        generation += 1
        do {
            let graph = try DispatchQueue.global(qos: .userInitiated).sync {
                try database.fetchSlice(tables)
            }
            apply(graph, tables: tables)
        } catch {
            let description = error.localizedDescription
            AppLog.persistence.error("Could not reload the journal: \(description, privacy: .public)")
            onReadFailure?(description)
        }
    }

    private func apply(_ graph: AppDatabase.StoredGraph, tables: JournalTables) {
        if tables.contains(.loads) { loads = graph.loads }
        if tables.contains(.paychecks) { paychecks = graph.paychecks }
        if tables.contains(.diesel) { diesel = graph.diesel }
        if tables.contains(.maintenance) {
            maintenance = graph.maintenance
            maintenanceArchive = graph.maintenanceArchive
        }
        if tables.contains(.photos) { photos = graph.photos }
        if tables.contains(.scans) { scans = graph.scans }
        if tables.contains(.profile) { profile = graph.profile }
        if tables.contains(.expenses) { expenses = graph.expenses }
        if tables.contains(.perDiem) { perDiemOverrides = graph.perDiemOverrides }
        if tables.contains(.loads) || tables.contains(.photos) || tables.contains(.scans) {
            relinkMedia()
        }
    }

    /// Photos and scans live in their own tables. A load-only refresh still has to point them
    /// at the load rows the screen already holds.
    private func relinkMedia() {
        let loadsById = Dictionary(uniqueKeysWithValues: loads.map { ($0.id, $0) })
        for load in loads {
            load.photos = nil
            load.scans = nil
        }
        for photo in photos {
            guard let loadId = photo.loadId, let load = loadsById[loadId] else {
                photo.load = nil
                continue
            }
            photo.load = load
            load.photos = (load.photos ?? []) + [photo]
        }
        for scan in scans {
            guard let loadId = scan.loadId, let load = loadsById[loadId] else {
                scan.load = nil
                continue
            }
            scan.load = load
            load.scans = (load.scans ?? []) + [scan]
        }
    }
}
