import Foundation

/// What to do with a journal file whose Keychain passphrase is gone.
///
/// The passphrase item is `ThisDeviceOnly`, so a phone restored from a device backup (or a new
/// phone) gets the encrypted file but not the key. The file can never be opened again, and a
/// new key can only open a new file. The old file is moved aside, never deleted, so nothing is
/// lost that was recoverable. The driver restores from iCloud into the new journal.
enum JournalKeyLoss {

    static let suffixes = ["", "-wal", "-shm"]

    /// True when a non-empty journal file exists at `url`.
    static func journalExists(at url: URL, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size > 0
    }

    /// Renames the journal and its WAL/SHM sidecars to `<name>.unreadable-<stamp>`.
    /// Returns the new location of the main file.
    @discardableResult
    static func moveAside(
        databaseURL url: URL,
        stamp: Int = Int(Date().timeIntervalSince1970),
        fileManager: FileManager = .default
    ) throws -> URL {
        let target = URL(fileURLWithPath: url.path + ".unreadable-\(stamp)")
        for suffix in suffixes {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: target.path + suffix)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        }
        return target
    }
}

/// Owns the encrypted database for the local journal.
///
/// A previous Sign in with Apple file is adopted first (see `LocalStoreMigration`). A SwiftData
/// file from the build before SQLCipher is then copied in. If the encrypted file cannot be
/// opened, the UI still comes up on an empty in-memory database. That database saves nothing,
/// so `isEphemeral` is set and the app shows a banner; iCloud backup is not bound to it, and
/// can therefore not overwrite the real backup with a few throwaway rows.
@Observable
final class PersistenceController {

    private(set) var scope: AccountScope
    let database: AppDatabase
    /// Set when the on-disk store could not be opened or the SwiftData copy failed.
    private(set) var storeFailure: String?
    /// True when this run uses a throwaway in-memory database: nothing entered is saved.
    private(set) var isEphemeral = false
    /// True when an unreadable journal (its Keychain key is gone) was moved aside and a new
    /// journal started. The old file is kept next to the new one.
    private(set) var recoveredFromKeyLoss = false

    init(scope: AccountScope = .local) {
        self.scope = scope
        var failure: String?
        var ephemeral = false
        var recovered = false
        let opened: AppDatabase
        do {
            let url = try AccountScopedContainer.databaseURL(for: scope)
            let keychain = DatabasePassphraseStore(account: scope.storeKey)
            if try keychain.read() == nil, JournalKeyLoss.journalExists(at: url) {
                try JournalKeyLoss.moveAside(databaseURL: url)
                recovered = true
                AppLog.persistence.notice("Journal key missing; unreadable journal moved aside")
            }
            let passphrase = try keychain.getOrCreate()
            let database = try AppDatabase.open(at: url, passphrase: passphrase)
            opened = database
            do {
                let legacy = try AccountScopedContainer.storeURL(for: scope)
                _ = try SwiftDataMigration.run(legacyStoreURL: legacy, database: database)
            } catch {
                failure = error.localizedDescription
                AppLog.persistence.error("SwiftData import failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            failure = error.localizedDescription
            AppLog.persistence.error("Encrypted store failed to open: \(error.localizedDescription, privacy: .public)")
            guard let fallback = try? AppDatabase.ephemeral() else {
                fatalError("SQLCipher could not open a store, even in memory: \(error)")
            }
            opened = fallback
            ephemeral = true
        }
        self.database = opened
        self.storeFailure = failure
        self.isEphemeral = ephemeral
        self.recoveredFromKeyLoss = recovered
    }

    /// Preview / test store. Does not touch the Keychain or the SwiftData file.
    init(database: AppDatabase, scope: AccountScope = .local) {
        self.scope = scope
        self.database = database
    }
}
