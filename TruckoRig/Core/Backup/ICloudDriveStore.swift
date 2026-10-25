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
        case missing
        case tooLarge
        case refusedSecret
    }

    let probe: Probe
    private let fileManager: FileManager
    private var cachedContainerURL: URL?
    /// Test hook. These relative paths behave as ubiquity items that are not on disk yet.
    var notDownloadedRelativePaths: Set<String> = []
    private(set) var downloadRequests: [String] = []
    private(set) var mediaWrites: [String] = []
    private(set) var manifestWriteCount = 0

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
        if ICloudMediaPolicy.documentIsSecret(Array(data)) { throw Failure.refusedSecret }
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

    func mediaRoot(accountId: String) -> URL? {
        documentsURL()?
            .appendingPathComponent(ICloudMediaPolicy.folderName, isDirectory: true)
            .appendingPathComponent(BackupAccount.sanitizeFilePart(accountId), isDirectory: true)
    }

    func manifestURL(accountId: String) -> URL? {
        mediaRoot(accountId: accountId)?
            .appendingPathComponent(ICloudMediaPolicy.manifestFileName, isDirectory: false)
    }

    /// `nil` when this account has no manifest yet.
    func readManifest(accountId: String) throws -> Data? {
        guard availability() == .available, let url = manifestURL(accountId: accountId) else {
            throw Failure.unavailable
        }
        if notDownloadedRelativePaths.contains(ICloudMediaPolicy.manifestFileName) || isWaitingForDownload(url) {
            demandDownload(url, relativePath: ICloudMediaPolicy.manifestFileName)
            throw Failure.notDownloaded
        }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try coordinatedRead(url)
    }

    func writeManifest(_ data: Data, accountId: String) throws {
        guard availability() == .available, let url = manifestURL(accountId: accountId) else {
            throw Failure.unavailable
        }
        if ICloudMediaPolicy.documentIsSecret(Array(data)) { throw Failure.refusedSecret }
        try createParent(of: url)
        let exists = fileManager.fileExists(atPath: url.path)
        try coordinatedWrite(data, to: url, options: exists ? .forReplacing : [])
        manifestWriteCount += 1
    }

    /// Reads one media file. A not-yet-local ubiquity item starts downloading and throws
    /// `notDownloaded`. A path that was never uploaded throws `missing`. Neither deletes anything.
    func readMedia(accountId: String, relativePath: String) throws -> Data {
        guard availability() == .available,
              let url = mediaFileURL(accountId: accountId, relativePath: relativePath)
        else { throw Failure.unavailable }
        if notDownloadedRelativePaths.contains(relativePath) || isWaitingForDownload(url) {
            demandDownload(url, relativePath: relativePath)
            throw Failure.notDownloaded
        }
        guard fileManager.fileExists(atPath: url.path) else { throw Failure.missing }
        return try coordinatedRead(url)
    }

    func writeMedia(_ data: Data, accountId: String, relativePath: String) throws {
        guard availability() == .available,
              let url = mediaFileURL(accountId: accountId, relativePath: relativePath)
        else { throw Failure.unavailable }
        if data.count > ICloudMediaPolicy.maxFileBytes { throw Failure.tooLarge }
        if ICloudMediaPolicy.fileIsSecret(Array(data)) { throw Failure.refusedSecret }
        try createParent(of: url)
        let exists = fileManager.fileExists(atPath: url.path)
        try coordinatedWrite(data, to: url, options: exists ? .forReplacing : [])
        mediaWrites.append(relativePath)
    }

    private func mediaFileURL(accountId: String, relativePath: String) -> URL? {
        guard let root = mediaRoot(accountId: accountId) else { return nil }
        let parts = relativePath.split(separator: "/").map(String.init)
        guard parts.count == 2,
              parts[0] == ICloudMediaPolicy.photoDirectory || parts[0] == ICloudMediaPolicy.scanDirectory,
              ICloudMediaPolicy.canonicalRelativePath(
                kind: parts[0] == ICloudMediaPolicy.photoDirectory
                    ? ICloudMediaPolicy.Kind.photo
                    : ICloudMediaPolicy.Kind.scan,
                fileName: parts[1]
              ) == relativePath
        else { return nil }
        let url = root.appendingPathComponent(parts[0], isDirectory: true).appendingPathComponent(parts[1])
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        return url
    }

    private func createParent(of url: URL) throws {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw Failure.writeFailed
        }
    }

    private func demandDownload(_ url: URL, relativePath: String) {
        downloadRequests.append(relativePath)
        try? fileManager.startDownloadingUbiquitousItem(at: url)
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
        start(fileNames: [fileName], onUpdate: onUpdate)
    }

    func start(fileNames: [String], onUpdate: @escaping () -> Void) {
        stop()
        self.onUpdate = onUpdate
        query.searchScopes = [ICloudMetadataQueryPlan.ubiquitousDocumentsScope]
        let predicates = fileNames.map { ICloudMetadataQueryPlan.predicate(fileName: $0) }
        query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
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
