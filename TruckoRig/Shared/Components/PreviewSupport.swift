#if DEBUG
import SwiftUI

/// Wraps a preview in the environment the app provides: an in-memory encrypted store and a fresh
/// `AppState`.
@MainActor
struct PreviewHost<Content: View>: View {

    @ViewBuilder let content: Content
    @State private var appState: AppState

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        let database: AppDatabase
        do {
            database = try AppDatabase.ephemeral()
        } catch {
            fatalError("Preview store failed to open: \(error)")
        }
        _appState = State(initialValue: AppState(persistence: PersistenceController(database: database)))
    }

    var body: some View {
        content
            .environment(appState)
            .tint(.forestPrimary)
    }
}
#endif
