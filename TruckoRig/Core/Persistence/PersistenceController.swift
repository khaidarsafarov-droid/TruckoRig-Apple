import Foundation

/// Owns the encrypted database for the local journal.
///
/// A previous Sign in with Apple file is adopted first (see `LocalStoreMigration`). A SwiftData
/// file from the build before SQLCipher is then copied in. If the encrypted file cannot be
/// opened, the UI still comes up on an empty in-memory database and Settings shows the failure.
@Observable
final class PersistenceController {

    private(set) var scope: AccountScope
    let database: AppDatabase
    /// Set when the on-disk store could not be opened or the SwiftData copy failed.
    private(set) var storeFailure: String?

    init(scope: AccountScope = .local) {
        self.scope = scope
        do {
            let url = try AccountScopedContainer.databaseURL(for: scope)
            let passphrase = try DatabasePassphraseStore(account: scope.storeKey).getOrCreate()
            let database = try AppDatabase.open(at: url, passphrase: passphrase)
            self.database = database
            do {
                _ = try SwiftDataMigration.run(
                    legacyStoreURL: try AccountScopedContainer.storeURL(for: scope),
                    database: database
                )
            } catch {
                storeFailure = error.localizedDescription
                AppLog.persistence.error("SwiftData import failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            storeFailure = error.localizedDescription
            AppLog.persistence.error("Encrypted store failed to open: \(error.localizedDescription, privacy: .public)")
            guard let fallback = try? AppDatabase.ephemeral() else {
                fatalError("SQLCipher could not open a store, even in memory: \(error)")
            }
            database = fallback
        }
    }

    /// Preview / test store. Does not touch the Keychain or the SwiftData file.
    init(database: AppDatabase, scope: AccountScope = .local) {
        self.scope = scope
        self.database = database
    }
}
