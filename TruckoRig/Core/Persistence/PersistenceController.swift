import Foundation
import SwiftData

/// Owns the currently open database.
///
/// The whole app reads through the container this hands out. The store is local-only: there is
/// no account switch, and a previous Apple-scoped file is adopted once on upgrade.
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
