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

    /// What is still waiting to reach the server, for the offline indicator and the settings
    /// diagnostics row.
    struct PendingChanges: Equatable {
        var count = 0
        var oldest: Date?
        var retries = 0
        var lastError: String?
    }

    private(set) var state: State = .idle
    private(set) var lastSyncedAt: Date?
    private(set) var pending = PendingChanges()

    var pendingCount: Int { pending.count }

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
        pending.count += 1
        if pending.oldest == nil { pending.oldest = Date() }
    }

    func refreshPending() {
        let descriptor = FetchDescriptor<SyncOutbox>(sortBy: [SortDescriptor(\.timestamp)])
        let rows = (try? persistence.mainContext.fetch(descriptor)) ?? []
        pending = PendingChanges(
            count: rows.count,
            oldest: rows.first?.timestamp,
            retries: rows.first?.retryCount ?? 0,
            lastError: rows.compactMap(\.lastError).last
        )
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

            // Media first: the outbox is cleared at the end, and a photo whose bytes never left
            // the phone must not be forgotten.
            await uploadPendingMedia(client: client, in: context)

            // Push before pulling: the driver's phone is the source of truth for anything typed
            // offline, and last-write-wins on the server then folds in other devices.
            try await client.send(Endpoints.pushSnapshot(snapshot))
            try await pullIfChanged(client: client, in: context)

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
            try await pullIfChanged(client: client, in: persistence.mainContext)
            lastSyncedAt = Date()
        } catch {
            AppLog.sync.error("Pull failed")
        }
    }

    /// Downloads and applies the server snapshot, unless the server's cursor says nothing moved.
    ///
    /// The cursor check is one small request against a whole-account snapshot, which matters on a
    /// phone tethered to a hotspot in the middle of a run.
    private func pullIfChanged(client: APIClient, in context: ModelContext) async throws {
        let remoteCursor = try? await client.send(Endpoints.fetchCursor, as: SyncCursor.self)
        if let remoteCursor, !remoteCursor.value.isEmpty, remoteCursor.value == settings.lastSyncCursor {
            AppLog.sync.debug("Server cursor unchanged; skipping snapshot download")
            return
        }

        let remote = try await client.send(Endpoints.fetchSnapshot, as: AccountCloudSnapshot.self)
        try SnapshotApplier.apply(remote, to: context, week: settings.truckingWeek)

        if let remoteCursor {
            settings.lastSyncCursor = remoteCursor.value
        } else {
            // No cursor from the server: publish one derived from what we just applied, so the
            // next sync has something to compare against.
            let cursor = SyncCursor(value: ISO8601DateFormatter().string(from: remote.updatedAt), updatedAt: Date())
            try? await client.send(Endpoints.pushCursor(cursor))
            settings.lastSyncCursor = cursor.value
        }
    }

    /// Uploads photos and scans whose bytes are still only on this phone.
    ///
    /// Best effort per file: one rejected upload must not stop the rest, and a file the driver
    /// deleted from disk is dropped from the queue instead of retried forever.
    private func uploadPendingMedia(client: APIClient, in context: ModelContext) async {
        let uploader = MediaUploader(client: client, store: MediaStore(scope: persistence.scope))

        let photos = (try? context.fetch(FetchDescriptor<Photo>(predicate: #Predicate { $0.isUploaded == false }))) ?? []
        for photo in photos {
            do {
                photo.cloudPath = try await uploader.upload(
                    fileName: photo.fileName,
                    kind: .photo,
                    entityType: .photo,
                    entityId: photo.id
                )
                photo.isUploaded = true
            } catch MediaUploadError.fileMissing {
                AppLog.media.notice("Photo file is gone; marking it as not pending")
                photo.isUploaded = true
            } catch {
                AppLog.media.error("Photo upload failed")
            }
        }

        let scans = (try? context.fetch(FetchDescriptor<Scan>(predicate: #Predicate { $0.isUploaded == false }))) ?? []
        for scan in scans {
            do {
                scan.cloudPath = try await uploader.upload(
                    fileName: scan.fileName,
                    kind: .scan,
                    entityType: .scan,
                    entityId: scan.id
                )
                scan.isUploaded = true
            } catch MediaUploadError.fileMissing {
                AppLog.media.notice("Scan file is gone; marking it as not pending")
                scan.isUploaded = true
            } catch {
                AppLog.media.error("Scan upload failed")
            }
        }

        try? context.save()
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
        pending = PendingChanges()
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
        refreshPending()
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
