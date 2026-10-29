import SwiftUI

@main
struct TruckoRigApp: App {

    @State private var appState = AppState()

    init() {
        TelegramBackgroundRegistrar.register()
        ICloudBackgroundRegistrar.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(.forestPrimary)
                .modifier(AppCabinTheme(
                    mode: appState.settings.themeMode,
                    oledDark: appState.settings.oledDark,
                    reduceMotion: appState.settings.reduceMotion
                ))
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
