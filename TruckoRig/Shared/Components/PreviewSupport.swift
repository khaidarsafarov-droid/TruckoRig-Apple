#if DEBUG
import SwiftData
import SwiftUI

/// Wraps a preview in the environment the app normally provides: an in-memory store and a fresh
/// `AppState`. Without it, any view holding a `@Query` traps as soon as the preview renders.
@MainActor
struct PreviewHost<Content: View>: View {

    @ViewBuilder let content: Content

    @State private var appState = AppState()
    private let container = try? AccountScopedContainer.makeInMemory()

    var body: some View {
        Group {
            if let container {
                content.modelContainer(container)
            } else {
                content
            }
        }
        .environment(appState)
        .tint(.forestPrimary)
    }
}
#endif
