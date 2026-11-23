import Foundation

/// Copies a pre-encryption SwiftData store into the SQLCipher database, once.
///
/// The old file is `TruckoRig_<scope>.store` (plus `-wal` / `-shm`). It stays put until the
/// encrypted copy and its completion marker commit. After that the plaintext file is deleted.
/// Flash storage does not offer a reliable overwrite, so deletion is `FileManager.removeItem`,
/// which is what Apple documents for removing a file. A later launch also deletes any
/// `.premigration` copy left by an older build.
enum SwiftDataMigrationError: Error, LocalizedError, Equatable {
    case legacyUnreadable

    var errorDescription: String? {
        "The old journal could not be read, so it was left in place."
    }
}

enum SwiftDataMigration {

    enum Outcome: Equatable {
        case imported(Int)
        case alreadyImported
        case nothingToImport
    }

    static func run(
        legacyStoreURL: URL,
        database: AppDatabase,
        fileManager: FileManager = .default
    ) throws -> Outcome {
        if try database.legacyImportIsDone() {
            return .alreadyImported
        }
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            try database.markLegacyImportDone()
            return .nothingToImport
        }

        let journal = try LegacySwiftDataReader.read(storeURL: legacyStoreURL)
        if journal.isEmpty {
            if try LegacySwiftDataReader.containsUserTable(at: legacyStoreURL) {
                try database.markLegacyImportDone()
                return .nothingToImport
            }
            if hasBytes(legacyStoreURL, fileManager: fileManager)
                || hasBytes(URL(fileURLWithPath: legacyStoreURL.path + "-wal"), fileManager: fileManager) {
                throw SwiftDataMigrationError.legacyUnreadable
            }
            try database.markLegacyImportDone()
            return .nothingToImport
        }

        try database.importLegacy(journal)
        let counts = try database.tableCounts()
        guard counts.matches(journal) else {
            throw SwiftDataMigrationError.legacyUnreadable
        }
        try database.markLegacyImportDone()
        deleteVerified(legacyStoreURL, fileManager: fileManager)
        return .imported(journal.loads.count)
    }

    /// Names for one account only: `TruckoRig_<scope>.store`, its `-wal` and `-shm`, and the
    /// `.premigration` copies of those three. A sibling scope is not included.
    static func legacyFileNames(scopeKey: String) -> [String] {
        let base = "TruckoRig_\(scopeKey).store"
        return [
            base, base + "-wal", base + "-shm",
            base + ".premigration", base + "-wal.premigration", base + "-shm.premigration",
        ]
    }

    /// Deletes this scope's legacy files, including `.premigration`, after the row counts matched.
    static func deleteVerified(_ storeURL: URL, fileManager: FileManager = .default) {
        let directory = storeURL.deletingLastPathComponent()
        let scopeKey = scopeKey(from: storeURL)
        for name in legacyFileNames(scopeKey: scopeKey) {
            remove(directory.appendingPathComponent(name), fileManager: fileManager)
        }
    }

    /// Deletes only this scope's leftover plaintext files. Another scope's store is left alone.
    static func deleteLeftovers(in directory: URL, scopeKey: String, fileManager: FileManager = .default) {
        for name in legacyFileNames(scopeKey: scopeKey) {
            remove(directory.appendingPathComponent(name), fileManager: fileManager)
        }
    }

    private static func scopeKey(from storeURL: URL) -> String {
        var name = storeURL.deletingPathExtension().lastPathComponent
        let prefix = "TruckoRig_"
        if name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        return name
    }

    private static func hasBytes(_ url: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size > 0
    }

    private static func remove(_ url: URL, fileManager: FileManager) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            AppLog.persistence.error("Could not delete leftover store file \(url.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .public)")
        }
    }
}
