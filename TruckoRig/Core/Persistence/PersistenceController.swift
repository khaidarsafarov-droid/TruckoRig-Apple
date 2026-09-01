import Foundation
import SwiftData

/// Owns the currently open database and swaps it when the signed-in account changes.
///
/// The whole app reads through the container this hands out, so replacing it is what makes
/// account isolation real: no view can hold a context for a database that is no longer current.
@Observable
final class PersistenceController {

    private(set) var scope: AccountScope
    private(set) var container: ModelContainer
    /// Set when the on-disk store could not be opened and an in-memory fallback is in use.
    private(set) var storeFailure: String?

    @MainActor
    var mainContext: ModelContext { container.mainContext }

    init(scope: AccountScope = .local) {
        self.scope = scope
        let (container, failure) = Self.openContainer(for: scope)
        self.container = container
        self.storeFailure = failure
    }

    /// Opens the database for `scope`, discarding the previous one.
    ///
    /// No-op when the scope has not changed, so a token refresh does not tear down the UI.
    func switchTo(_ scope: AccountScope) {
        guard scope != self.scope else { return }
        let (container, failure) = Self.openContainer(for: scope)
        self.scope = scope
        self.container = container
        self.storeFailure = failure
    }

    /// Signs out. `eraseStore` deletes the local database — used on an explicit "forget this
    /// account", not on a routine sign-out where the driver expects their data on next login.
    func signOut(eraseStore: Bool) {
        let previous = scope
        switchTo(.local)
        guard eraseStore, previous != .local else { return }
        try? AccountScopedContainer.destroyStore(for: previous)
    }

    /// Falls back to an in-memory store rather than crashing: a driver mid-trip needs the app to
    /// open even if the store is corrupt, and the failure surfaces in Settings.
    private static func openContainer(for scope: AccountScope) -> (ModelContainer, String?) {
        do {
            return (try AccountScopedContainer.make(for: scope), nil)
        } catch {
            let fallback = try? AccountScopedContainer.makeInMemory()
            guard let fallback else {
                fatalError("SwiftData could not open a store, even in memory: \(error)")
            }
            return (fallback, String(describing: error))
        }
    }
}
