import Foundation

/// Android v2 JSON backup written and read through Files.
///
/// The file name matches Android `BackupSchema.jsonFileName`. Restore is a full replace
/// (`BackupService.restoreBackupJson`): schema newer than v2 is rejected, a leading UTF-8 BOM
/// is ignored, and a journal newer than the file asks for confirmation first.
enum BackupService {

    struct ExportFile: Equatable {
        var data: Data
        var fileName: String
        var loadCount: Int
    }

    struct Preview: Equatable {
        var json: String
        var exportedAt: Int64
        var unbound: Bool
    }

    struct Report: Equatable {
        var loads: Int
        var paychecks: Int
        var diesel: Int
    }

    enum Failure: Error, Equatable {
        case readFailed
        case invalidFormat
        case corrupted
        case chartNote
        case schemaTooNew(Int)
        case wrongAccount
        case unboundAccount
        case tooLarge
        case empty
    }

    static func exportFile(
        from database: AppDatabase,
        settings: AppSettings,
        identity: BackupIdentityStore,
        accountId: String = BackupAccount.localDev,
        exportedAt: Int64 = nowMillis()
    ) throws -> ExportFile {
        let backup = BackupJournalMapper.export(
            graph: try database.fetchGraph(),
            settings: settings,
            identity: identity,
            accountId: accountId,
            exportedAt: exportedAt
        )
        guard BackupDataCodec.hasExportableContent(backup) else { throw Failure.empty }
        let json = BackupDataCodec.encode(backup)
        return ExportFile(
            data: Data(json.utf8),
            fileName: BackupSchema.jsonFileName(exportedAt: backup.exportedAt),
            loadCount: backup.loads.count
        )
    }

    /// Warn when local load activity is newer than the file about to replace it.
    static func shouldWarnBeforeRestore(localNewestMillis: Int64, backupExportedAt: Int64) -> Bool {
        BackupSyncPolicy.shouldWarnBeforeFileRestore(
            localNewestMillis: localNewestMillis,
            backupExportedAt: backupExportedAt
        )
    }

    static func shouldWarnBeforeRestore(in database: AppDatabase, backupExportedAt: Int64) throws -> Bool {
        let loads = try database.fetchGraph().loads
        let newest = loads.map { max(millis($0.updatedAt), millis($0.parsedAt)) }.max() ?? 0
        return shouldWarnBeforeRestore(localNewestMillis: newest, backupExportedAt: backupExportedAt)
    }

    static func preview(data: Data, activeAccountId: String = BackupAccount.localDev) throws -> Preview {
        if data.count > BackupSchedule.maxRestoreBytes { throw Failure.tooLarge }
        let json = try jsonText(from: data)
        let backup = try decode(json)
        let account = backup.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let active = activeAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !account.isEmpty && !active.isEmpty && account != active {
            throw Failure.wrongAccount
        }
        return Preview(json: json, exportedAt: backup.exportedAt, unbound: account.isEmpty)
    }

    static func read(url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: BackupSchedule.maxRestoreBytes + 1) ?? Data()
        } catch let error as Failure {
            throw error
        } catch {
            throw Failure.readFailed
        }
        if data.count > BackupSchedule.maxRestoreBytes { throw Failure.tooLarge }
        return data
    }

    /// Full replace of the journal. Schema v1 leaves maintenance in place. Photos and scans
    /// linked to a removed load are deleted; other media on this phone stays.
    /// Week reindexing touches the main-actor journal cache, so restore runs there too.
    @MainActor
    @discardableResult
    static func restoreBackupJSON(
        _ json: String,
        into database: AppDatabase,
        settings: AppSettings,
        identity: BackupIdentityStore,
        media: MediaStore,
        activeAccountId: String = BackupAccount.localDev,
        allowUnboundAccount: Bool
    ) throws -> Report {
        if json.utf8.count > BackupSchedule.maxRestoreBytes { throw Failure.tooLarge }
        let backup = try decode(json)
        let account = backup.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let active = activeAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.isEmpty {
            if !allowUnboundAccount { throw Failure.unboundAccount }
        } else if !active.isEmpty && account != active {
            throw Failure.wrongAccount
        }
        let previousWeek = settings.weekStart
        let plan = BackupJournalMapper.importBackup(backup, settings: settings, identity: identity)
        let removed = try database.applyBackupJournal(plan)
        for photo in removed.photos {
            media.delete(fileName: photo.fileName, filePath: photo.filePath, kind: .photo)
        }
        for scan in removed.scans {
            media.delete(fileName: scan.fileName, filePath: scan.filePath, kind: .scan)
        }
        if settings.weekStart != previousWeek {
            try WeekReindexer.reindex(in: database, week: settings.truckingWeek)
        }
        if let profile = try database.fetchGraph().profile {
            profile.weeklyGoal = settings.weeklyGoal
            try database.save(profile)
        }
        return Report(loads: backup.loads.count, paychecks: backup.paychecks.count, diesel: backup.diesel.count)
    }

    static func userMessage(for error: Failure) -> String {
        switch error {
        case .readFailed:
            return String(localized: "settings.backup.readFailed")
        case .invalidFormat:
            return String(localized: "settings.backup.badFormat")
        case .corrupted:
            return String(localized: "settings.backup.corrupted")
        case .chartNote:
            return String(localized: "settings.backup.chartNote")
        case .schemaTooNew:
            return String(localized: "settings.backup.schema")
        case .wrongAccount:
            return String(localized: "settings.backup.wrongAccount")
        case .unboundAccount:
            return String(localized: "settings.backup.unbound")
        case .tooLarge:
            return String(localized: "settings.backup.tooLarge")
        case .empty:
            return String(localized: "settings.backup.error")
        }
    }

    private static func jsonText(from data: Data) throws -> String {
        do {
            return try BackupRestoreParser.parseToJSON(data)
        } catch let error as BackupParseFailure {
            switch error {
            case .invalidFormat: throw Failure.invalidFormat
            case .chartNote: throw Failure.chartNote
            }
        } catch {
            throw Failure.invalidFormat
        }
    }

    private static func decode(_ json: String) throws -> BackupData {
        do {
            return try BackupDataCodec.decode(json)
        } catch let error as BackupDecodeError {
            switch error {
            case .invalidFormat: throw Failure.invalidFormat
            case .corrupted: throw Failure.corrupted
            case .schemaTooNew(let version): throw Failure.schemaTooNew(version)
            }
        } catch {
            throw Failure.corrupted
        }
    }

    private static func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
