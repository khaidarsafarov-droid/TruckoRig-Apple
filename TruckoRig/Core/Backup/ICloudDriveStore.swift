import Foundation

/// Reads and writes the one backup file in the iCloud Drive ubiquity container.
///
/// Production uses `FileManager` ubiquity APIs. Tests pass a directory and never touch iCloud.
/// Bytes go through `NSFileCoordinator`. `NSMetadataQuery` watches the live container.
final class ICloudDriveStore {
    enum Probe {
        case system
        case available(URL)
        case signedOut
        case containerMissing
    }

    enum Failure: Error, Equatable {
        case unavailable
        case coordinationFailed
        case readFailed
        case writeFailed
        case notDownloaded
        case tooLarge
    }

    let probe: Probe
    private let fileManager: FileManager
    private var cachedContainerURL: URL?

    init(probe: Probe = .system, fileManager: FileManager = .default) {
        self.probe = probe
        self.fileManager = fileManager
    }

    var monitorsUbiquity: Bool {
        if case .system = probe { return true }
        return false
    }

    func availability() -> ICloudBackupPolicy.Availability {
        switch probe {
        case .system:
            return ICloudDriveProbe.systemAvailability(fileManager: fileManager)
        case .available:
            return .available
        case .signedOut:
            return .signedOut
        case .containerMissing:
            return .containerMissing
        }
    }

    func containerURL() -> URL? {
        if let cachedContainerURL { return cachedContainerURL }
        let resolved: URL?
        switch probe {
        case .available(let root):
            resolved = root
        case .signedOut, .containerMissing:
            resolved = nil
        case .system:
            resolved = fileManager.url(forUbiquityContainerIdentifier: ICloudBackupPolicy.containerIdentifier)
        }
        cachedContainerURL = resolved
        return resolved
    }

    func documentsURL() -> URL? {
        containerURL()?.appendingPathComponent("Documents", isDirectory: true)
    }

    func backupURL(accountId: String) -> URL? {
        documentsURL()?.appendingPathComponent(
            ICloudBackupPolicy.containerFileName(accountId: accountId),
            isDirectory: false
        )
    }

    /// `nil` when the account has no file yet. A not-yet-downloaded ubiquity item throws
    /// `notDownloaded` and asks the system to fetch it. That is not the same as "no file".
    func read(accountId: String) throws -> Data? {
        guard availability() == .available, let url = backupURL(accountId: accountId) else {
            throw Failure.unavailable
        }
        if isWaitingForDownload(url) {
            try? fileManager.startDownloadingUbiquitousItem(at: url)
            throw Failure.notDownloaded
        }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try resolveConflicts(at: url) ?? coordinatedRead(url)
        if data.count > BackupSchedule.maxRestoreBytes { throw Failure.tooLarge }
        return data
    }

    func write(_ data: Data, accountId: String) throws {
        guard availability() == .available, let url = backupURL(accountId: accountId) else {
            throw Failure.unavailable
        }
        if data.count > BackupSchedule.maxRestoreBytes { throw Failure.tooLarge }
        guard let documents = documentsURL() else { throw Failure.unavailable }
        do {
            try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        } catch {
            throw Failure.writeFailed
        }
        let exists = fileManager.fileExists(atPath: url.path)
        try coordinatedWrite(data, to: url, options: exists ? .forReplacing : [])
        _ = try? resolveConflicts(at: url)
    }

    private func isWaitingForDownload(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ])
        guard values?.isUbiquitousItem == true else { return false }
        if let status = values?.ubiquitousItemDownloadingStatus {
            return status != .current
        }
        return !fileManager.fileExists(atPath: url.path)
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var payload: Data?
        var readFailed = false
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            do {
                payload = try Data(contentsOf: target)
            } catch {
                readFailed = true
            }
        }
        if coordinationError != nil { throw Failure.coordinationFailed }
        if readFailed || payload == nil { throw Failure.readFailed }
        return payload ?? Data()
    }

    private func coordinatedWrite(
        _ data: Data,
        to url: URL,
        options: NSFileCoordinator.WritingOptions
    ) throws {
        var coordinationError: NSError?
        var writeFailed = false
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { target in
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                writeFailed = true
            }
        }
        if coordinationError != nil { throw Failure.coordinationFailed }
        if writeFailed { throw Failure.writeFailed }
    }

    /// Keeps the conflict version with the newer `exportedAt` and drops the rest.
    private func resolveConflicts(at url: URL) throws -> Data? {
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        guard !conflicts.isEmpty, let current = NSFileVersion.currentVersionOfItem(at: url) else {
            return nil
        }
        var versions: [(NSFileVersion, Data, Int64)] = []
        if let data = try? coordinatedRead(current.url) {
            versions.append((current, data, Self.exportedAt(in: data)))
        }
        for conflict in conflicts {
            guard let data = try? coordinatedRead(conflict.url) else { continue }
            versions.append((conflict, data, Self.exportedAt(in: data)))
        }
        guard !versions.isEmpty else { return nil }
        let stamps = versions.map {
            ICloudBackupPolicy.VersionStamp(exportedAt: $0.2, isCurrent: $0.0 === current)
        }
        guard let index = ICloudBackupPolicy.winningVersionIndex(stamps) else { return nil }
        let winner = versions[index]
        if winner.0 !== current {
            try coordinatedWrite(winner.1, to: url, options: .forReplacing)
        }
        current.isResolved = true
        for conflict in conflicts {
            conflict.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        return winner.1
    }

    private static func exportedAt(in data: Data) -> Int64 {
        guard let text = try? BackupRestoreParser.parseToJSON(data),
              let backup = try? BackupDataCodec.decode(text)
        else { return 0 }
        return backup.exportedAt
    }
}

enum ICloudDriveProbe {
    static func systemAvailability(fileManager: FileManager = .default) -> ICloudBackupPolicy.Availability {
        guard fileManager.ubiquityIdentityToken != nil else { return .signedOut }
        guard fileManager.url(forUbiquityContainerIdentifier: ICloudBackupPolicy.containerIdentifier) != nil else {
            return .containerMissing
        }
        return .available
    }
}

/// `NSMetadataQuery` scoped to the ubiquity Documents folder and this account's file name.
final class ICloudMetadataWatcher: NSObject {
    private let query = NSMetadataQuery()
    private var onUpdate: (() -> Void)?
    private var observing = false
    private var started = false

    func start(fileName: String, onUpdate: @escaping () -> Void) {
        stop()
        self.onUpdate = onUpdate
        query.searchScopes = [ICloudMetadataQueryPlan.ubiquitousDocumentsScope]
        query.predicate = ICloudMetadataQueryPlan.predicate(fileName: fileName)
        query.notificationBatchingInterval = 1
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gather),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gather),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        observing = true
        started = query.start()
    }

    func stop() {
        if started { query.stop() }
        started = false
        if observing {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        }
        observing = false
        onUpdate = nil
    }

    @objc private func gather() {
        query.disableUpdates()
        onUpdate?()
        query.enableUpdates()
    }
}

enum ICloudMetadataQueryPlan {
    static let ubiquitousDocumentsScope = NSMetadataQueryUbiquitousDocumentsScope

    static func predicate(fileName: String) -> NSPredicate {
        NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
    }
}
