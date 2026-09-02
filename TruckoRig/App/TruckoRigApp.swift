import SwiftUI

@main
struct TruckoRigApp: App {

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                // Recreate the whole tree when the account store changes so @Query and
                // navigation never keep objects from the previous driver's database.
                .id(appState.persistence.scope.storeKey)
                .environment(appState)
                .modelContainer(appState.persistence.container)
                .tint(.forestPrimary)
                .environment(\.locale, resolvedLocale)
                .task {
                    await appState.bootstrap()
                }
        }
    }

    /// Honours the in-app language picker; `.system` falls through to the device setting.
    private var resolvedLocale: Locale {
        guard let identifier = appState.settings.language.localeIdentifier else { return .current }
        return Locale(identifier: identifier)
    }
}
