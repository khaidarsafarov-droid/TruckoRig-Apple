import BackgroundTasks
import Foundation
import Network

/// One media pass over the ubiquity container. It uploads changed files and never deletes.
struct ICloudMediaUploadReport: Equatable {
    enum Outcome: Equatable {
        case uploaded
        case unchanged
        case notDownloaded
        case unsupported
        case failed
    }

    var outcome: Outcome
    var uploaded: [String]
    var skipped: [String]
    var retained: [String]
    var refusedSecrets: [String]
    var wroteManifest: Bool
    var deletions: [String]
}

struct ICloudMediaApplyResult: Equatable {
    var payload: ICloudMediaRestorePayload
    var applied: ICloudMediaLibrary.Applied
}

struct ICloudRestoreOutcome: Equatable {
    var journal: BackupService.Report
    var media: ICloudMediaRestorePayload
    var applied: ICloudMediaLibrary.Applied
}

struct ICloudMediaRestorePayload: Equatable {
    var files: [ICloudMediaPolicy.Item]
    var bytes: [String: Data]
    var unavailable: [String]
    var unsupported: Bool
    var manifestNotReady: Bool
}

enum ICloudMediaManifestState: Equatable {
    case missing
    case ready(ICloudMediaPolicy.Manifest)
    case notDownloaded
    case unsupported(Int)
    case failed
}

final class ICloudMediaEngine {
    let store: ICloudDriveStore
    var downloadAttempts: Int
    var downloadPauseNanoseconds: UInt64

    init(store: ICloudDriveStore) {
        self.store = store
        self.downloadAttempts = store.monitorsUbiquity ? 8 : 1
        self.downloadPauseNanoseconds = store.monitorsUbiquity ? 500_000_000 : 0
    }

    func inspect(accountId: String) -> ICloudMediaManifestState {
        switch readManifest(accountId: accountId) {
        case .missing: return .missing
        case .ready(let manifest): return .ready(manifest)
        case .notDownloaded: return .notDownloaded
        case .unsupported(let version): return .unsupported(version)
        case .failed: return .failed
        }
    }

    @MainActor
    func upload(
        accountId: String,
        items: [ICloudMediaPolicy.Item],
        bytes: [String: Data],
        now: Int64
    ) -> ICloudMediaUploadReport {
        let prepared = prepare(items: items, bytes: bytes)
        switch readManifest(accountId: accountId) {
        case .notDownloaded:
            return report(outcome: .notDownloaded, refused: prepared.refused)
        case .unsupported:
            return report(outcome: .unsupported, refused: prepared.refused)
        case .failed:
            return report(outcome: .failed, refused: prepared.refused)
        case .missing:
            return write(accountId: accountId, local: prepared.items, bytes: prepared.bytes, remote: [], refused: prepared.refused, now: now)
        case .ready(let manifest):
            return write(
                accountId: accountId,
                local: prepared.items,
                bytes: prepared.bytes,
                remote: manifest.items,
                refused: prepared.refused,
                now: now
            )
        }
    }

    @MainActor
    func restore(
        accountId: String,
        onProgress: @escaping (ICloudMediaPolicy.Progress) -> Void
    ) async -> ICloudMediaRestorePayload {
        let manifest: ICloudMediaPolicy.Manifest
        switch readManifest(accountId: accountId) {
        case .missing:
            return ICloudMediaRestorePayload(files: [], bytes: [:], unavailable: [], unsupported: false, manifestNotReady: false)
        case .notDownloaded:
            onProgress(ICloudMediaPolicy.Progress(completed: 0, total: 0, unavailable: 0))
            return ICloudMediaRestorePayload(files: [], bytes: [:], unavailable: [], unsupported: false, manifestNotReady: true)
        case .unsupported:
            return ICloudMediaRestorePayload(files: [], bytes: [:], unavailable: [], unsupported: true, manifestNotReady: false)
        case .failed:
            return ICloudMediaRestorePayload(files: [], bytes: [:], unavailable: [], unsupported: false, manifestNotReady: false)
        case .ready(let ready):
            manifest = ready
        }

        var files: [ICloudMediaPolicy.Item] = []
        var payload: [String: Data] = [:]
        var unavailable: [String] = []
        let total = manifest.items.count
        onProgress(ICloudMediaPolicy.Progress(completed: 0, total: total, unavailable: 0))
        for item in manifest.items {
            if Task.isCancelled { break }
            let data = await readWithRetry(accountId: accountId, relativePath: item.relativePath)
            let hash = data.map { ICloudMediaPolicy.contentHash(Array($0)) } ?? ""
            let matches = data != nil && (item.contentHash.isEmpty || hash == item.contentHash)
            if let data, matches, !ICloudMediaPolicy.fileIsSecret(Array(data)) {
                files.append(item)
                payload[item.relativePath] = data
            } else {
                unavailable.append(item.relativePath)
            }
            onProgress(ICloudMediaPolicy.Progress(
                completed: files.count + unavailable.count,
                total: total,
                unavailable: unavailable.count
            ))
            await Task.yield()
        }
        return ICloudMediaRestorePayload(
            files: files,
            bytes: payload,
            unavailable: unavailable,
            unsupported: false,
            manifestNotReady: false
        )
    }

    private func write(
        accountId: String,
        local: [ICloudMediaPolicy.Item],
        bytes: [String: Data],
        remote: [ICloudMediaPolicy.Item],
        refused: [String],
        now: Int64
    ) -> ICloudMediaUploadReport {
        let plan = ICloudMediaPolicy.plan(local: local, remote: remote)
        var uploaded: [String] = []
        for item in plan.upload {
            guard let data = bytes[item.relativePath] else { continue }
            do {
                try store.writeMedia(data, accountId: accountId, relativePath: item.relativePath)
                uploaded.append(item.relativePath)
            } catch ICloudDriveStore.Failure.refusedSecret {
                continue
            } catch {
                return report(
                    outcome: .failed,
                    uploaded: uploaded,
                    skipped: plan.unchanged.map(\.relativePath),
                    retained: plan.retained.map(\.relativePath),
                    refused: refused,
                    wroteManifest: false,
                    deletions: plan.deletions
                )
            }
        }
        var wroteManifest = false
        if plan.rewritesManifest {
            let manifest = ICloudMediaPolicy.Manifest(
                accountId: accountId,
                updatedAt: now,
                items: plan.manifestItems
            )
            let text = ICloudMediaPolicy.encode(manifest)
            guard !text.isEmpty else {
                return report(outcome: .failed, uploaded: uploaded, refused: refused, deletions: plan.deletions)
            }
            do {
                try store.writeManifest(Data(text.utf8), accountId: accountId)
                wroteManifest = true
            } catch {
                return report(outcome: .failed, uploaded: uploaded, refused: refused, deletions: plan.deletions)
            }
        }
        let outcome: ICloudMediaUploadReport.Outcome = (uploaded.isEmpty && !wroteManifest) ? .unchanged : .uploaded
        return report(
            outcome: outcome,
            uploaded: uploaded,
            skipped: plan.unchanged.map(\.relativePath),
            retained: plan.retained.map(\.relativePath),
            refused: refused,
            wroteManifest: wroteManifest,
            deletions: plan.deletions
        )
    }

    private func prepare(
        items: [ICloudMediaPolicy.Item],
        bytes: [String: Data]
    ) -> (items: [ICloudMediaPolicy.Item], bytes: [String: Data], refused: [String]) {
        var cleanItems: [ICloudMediaPolicy.Item] = []
        var cleanBytes: [String: Data] = [:]
        var refused: [String] = []
        for item in items {
            guard let relative = ICloudMediaPolicy.canonicalRelativePath(kind: item.kind, fileName: item.fileName),
                  let data = bytes[item.relativePath] ?? bytes[relative],
                  !data.isEmpty
            else { continue }
            if data.count > ICloudMediaPolicy.maxFileBytes { continue }
            if ICloudMediaPolicy.fileIsSecret(Array(data)) {
                refused.append(relative)
                continue
            }
            var copy = item
            copy.relativePath = relative
            copy.contentHash = ICloudMediaPolicy.contentHash(Array(data))
            copy.byteCount = Int64(data.count)
            cleanItems.append(copy)
            cleanBytes[relative] = data
        }
        return (cleanItems, cleanBytes, refused)
    }

    private enum ManifestRead {
        case missing
        case ready(ICloudMediaPolicy.Manifest)
        case notDownloaded
        case unsupported(Int)
        case failed
    }

    private func readManifest(accountId: String) -> ManifestRead {
        let data: Data?
        do {
            data = try store.readManifest(accountId: accountId)
        } catch ICloudDriveStore.Failure.notDownloaded {
            return .notDownloaded
        } catch {
            return .failed
        }
        guard let data, !data.isEmpty else { return .missing }
        guard let text = String(data: data, encoding: .utf8) else { return .failed }
        do {
            return .ready(try ICloudMediaPolicy.decode(text))
        } catch let error as ICloudMediaPolicy.ManifestError {
            if case .unsupported(let version) = error { return .unsupported(version) }
            return .failed
        } catch {
            return .failed
        }
    }

    private func readWithRetry(accountId: String, relativePath: String) async -> Data? {
        let attempts = max(downloadAttempts, 1)
        for attempt in 0..<attempts {
            do {
                return try store.readMedia(accountId: accountId, relativePath: relativePath)
            } catch ICloudDriveStore.Failure.notDownloaded {
                if attempt + 1 == attempts { return nil }
                if downloadPauseNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: downloadPauseNanoseconds)
                }
            } catch {
                return nil
            }
        }
        return nil
    }

    private func report(
        outcome: ICloudMediaUploadReport.Outcome,
        uploaded: [String] = [],
        skipped: [String] = [],
        retained: [String] = [],
        refused: [String] = [],
        wroteManifest: Bool = false,
        deletions: [String] = []
    ) -> ICloudMediaUploadReport {
        ICloudMediaUploadReport(
            outcome: outcome,
            uploaded: uploaded,
            skipped: skipped,
            retained: retained,
            refusedSecrets: refused,
            wroteManifest: wroteManifest,
            deletions: deletions
        )
    }
}

enum ICloudMediaBackground {
    static func submit(after delay: TimeInterval) {
        guard !UITestLaunch.suppressesSystemPrompts else { return }
        let request = BGProcessingTaskRequest(identifier: ICloudMediaPolicy.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: delay)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Wi-Fi is "not cellular". The processing task cannot ask for Wi-Fi itself.
final class ICloudPathMonitor {
    private let monitor = NWPathMonitor()
    private var started = false

    func start(onChange: @escaping (Bool) -> Void) {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let wifi = path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.isExpensive
            onChange(wifi)
        }
        monitor.start(queue: DispatchQueue(label: "truckorig.icloud.path"))
    }

    func stop() {
        guard started else { return }
        started = false
        monitor.cancel()
    }
}
