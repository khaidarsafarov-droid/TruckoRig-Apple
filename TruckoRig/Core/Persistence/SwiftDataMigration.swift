import Foundation

/// Copies a pre-encryption SwiftData store into the SQLCipher database, once.
///
/// The old file is `TruckoRig_<scope>.store` (plus `-wal` / `-shm`). It stays put until the
/// encrypted copy and its completion marker commit. After that it is renamed, not deleted, so a
/// bad import can still be recovered from the `.premigration` file.
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
            try database.markLegacyImportDone()
            quarantine(legacyStoreURL, fileManager: fileManager)
            return .nothingToImport
        }

        try database.importLegacy(journal)
        quarantine(legacyStoreURL, fileManager: fileManager)
        return .imported(journal.loads.count)
    }

    /// Moves the SwiftData file aside. A failure here does not undo the import: the marker
    /// already says it finished, and the original bytes are still on disk under the old name.
    private static func quarantine(_ storeURL: URL, fileManager: FileManager) {
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: source.path + ".premigration")
            if fileManager.fileExists(atPath: destination.path) { continue }
            do {
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                AppLog.persistence.error("Could not quarantine SwiftData file \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
