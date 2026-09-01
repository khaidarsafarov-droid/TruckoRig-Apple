import Foundation
import Observation
import SwiftData

/// Drives cloud synchronisation.
///
/// Local-first: every mutation is already committed to SwiftData before this runs, and an outbox
/// row records that it needs uploading. When sync is switched off — or no backend is configured —
/// the same snapshot is written to a local mirror file so the data is still exportable.
@MainActor
@Observable
final class SyncEngine {

    enum State: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastSyncedAt: Date?
    private(set) var pendingCount = 0

    private let settings: AppSettings
    private let auth: AuthManager
    private let persistence: PersistenceController

    init(settings: AppSettings, auth: AuthManager, persistence: PersistenceController) {
        self.settings = settings
        self.auth = auth
        self.persistence = persistence
    }

    var isConfigured: Bool { settings.resolvedBackendURL != nil && auth.isCloudAccount }

    // MARK: - Outbox

    /// Records a local change. Call inside the same save as the change itself.
    func enqueue(_ entityType: SyncEntityType, id: UUID, operation: SyncOperation, in context: ModelContext) {
        context.insert(SyncOutbox(entityType: entityType, entityId: id, operation: operation))
        pendingCount += 1
    }

    func refreshPendingCount() {
        let context = persistence.mainContext
        pendingCount = (try? context.fetchCount(FetchDescriptor<SyncOutbox>())) ?? 0
    }

    // MARK: - Sync

    func syncNow() async {
        guard state != .syncing else { return }
        state = .syncing
        defer { if state == .syncing { state = .idle } }

        let context = persistence.mainContext
        do {
            let snapshot = try SnapshotBuilder.build(from: context)

            guard isConfigured, let baseURL = settings.resolvedBackendURL else {
                try writeLocalMirror(snapshot)
                lastSyncedAt = Date()
                state = .idle
                return
            }

            let client = APIClient(baseURL: baseURL, tokens: auth)
            // Push first: the driver's phone is the source of truth for anything typed offline,
            // and last-write-wins on the server then folds in other devices.
            try await client.send(Endpoints.pushSnapshot(snapshot))
            let remote = try await client.send(Endpoints.fetchSnapshot, as: AccountCloudSnapshot.self)
            try SnapshotApplier.apply(remote, to: context, week: settings.truckingWeek)

            try clearOutbox(in: context)
            try writeLocalMirror(snapshot)
            lastSyncedAt = Date()
            state = .idle
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            AppLog.sync.error("Sync failed: \(message, privacy: .public)")
            markOutboxAttempt(error: message)
            state = .failed(message)
        }
    }

    /// Pulls without pushing. Used by silent push wake-ups.
    func pullOnly() async {
        guard isConfigured, let baseURL = settings.resolvedBackendURL, state != .syncing else { return }
        state = .syncing
        defer { if state == .syncing { state = .idle } }
        do {
            let client = APIClient(baseURL: baseURL, tokens: auth)
            let remote = try await client.send(Endpoints.fetchSnapshot, as: AccountCloudSnapshot.self)
            try SnapshotApplier.apply(remote, to: persistence.mainContext, week: settings.truckingWeek)
            lastSyncedAt = Date()
        } catch {
            AppLog.sync.error("Pull failed")
        }
    }

    // MARK: - Devices

    func registerDevice(pushToken: String?) async {
        guard isConfigured, let baseURL = settings.resolvedBackendURL else { return }
        let client = APIClient(baseURL: baseURL, tokens: auth)
        let deviceId = DeviceIdentity.current
        try? await client.send(Endpoints.registerDevice(deviceId: deviceId))
        if let pushToken {
            try? await client.send(Endpoints.updatePushToken(deviceId: deviceId, token: pushToken))
        }
    }

    // MARK: - Internals

    private func clearOutbox(in context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<SyncOutbox>()) {
            context.delete(row)
        }
        try context.save()
        pendingCount = 0
    }

    private func markOutboxAttempt(error: String) {
        let context = persistence.mainContext
        guard let rows = try? context.fetch(FetchDescriptor<SyncOutbox>()) else { return }
        for row in rows {
            row.retryCount += 1
            row.lastAttemptAt = Date()
            row.lastError = error
        }
        try? context.save()
        pendingCount = rows.count
    }

    /// Mirror file, so an account's data can be exported even with sync disabled.
    private func writeLocalMirror(_ snapshot: AccountCloudSnapshot) throws {
        let directory = try AccountScopedContainer.storeDirectory()
        let url = directory.appendingPathComponent("cloud_account_mirror_\(persistence.scope.storeKey).json")
        let data = try JSONEncoder.api.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}

/// Stable per-install device identifier for device registration and push routing.
enum DeviceIdentity {
    private static let key = "truckorig.deviceId"

    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}
