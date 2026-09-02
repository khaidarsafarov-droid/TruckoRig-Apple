import SwiftUI

@main
struct TruckoRigApp: App {

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .modelContainer(appState.persistence.container)
                .tint(.forestPrimary)
                .environment(\.locale, resolvedLocale)
                .task {
                    appState.bootstrap()
                }
        }
    }

    /// Honours the in-app language picker; `.system` falls through to the device setting.
    private var resolvedLocale: Locale {
        guard let identifier = appState.settings.language.localeIdentifier else { return .current }
        return Locale(identifier: identifier)
    }
}
