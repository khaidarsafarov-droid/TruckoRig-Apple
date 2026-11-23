import Foundation

/// Copies a pre-encryption SwiftData store into the SQLCipher database, once.
///
/// The old file is `TruckoRig_<scope>.store` (plus `-wal` / `-shm`). It stays put until the
/// encrypted copy and its completion marker commit. After that the plaintext file is deleted.
/// Flash storage does not offer a reliable overwrite, so deletion is `FileManager.removeItem`,
/// which is what Apple documents for removing a file. A later launch also deletes any
/// `.premigration` copy left by an older build.
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
            deletePlaintext(legacyStoreURL, fileManager: fileManager)
            return .nothingToImport
        }

        try database.importLegacy(journal)
        deletePlaintext(legacyStoreURL, fileManager: fileManager)
        return .imported(journal.loads.count)
    }

    /// Deletes the SwiftData file, its sidecars, and any `.premigration` rename from an older build.
    static func deletePlaintext(_ storeURL: URL, fileManager: FileManager = .default) {
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            remove(source, fileManager: fileManager)
            remove(URL(fileURLWithPath: source.path + ".premigration"), fileManager: fileManager)
        }
    }

    /// Deletes leftover plaintext stores in the account directory. The SQLCipher `.sqlite` file stays.
    static func deleteLeftovers(in directory: URL, fileManager: FileManager = .default) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names {
            let lower = name.lowercased()
            let plaintext = lower.contains(".store") || lower.hasSuffix(".premigration")
            guard plaintext, !lower.contains(".sqlite") else { continue }
            remove(directory.appendingPathComponent(name), fileManager: fileManager)
        }
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
