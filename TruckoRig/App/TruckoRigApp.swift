import SwiftUI

@main
struct TruckoRigApp: App {

    @State private var appState = AppState()

    init() {
        AppLocale.install()
        TelegramBackgroundRegistrar.register()
        ICloudBackgroundRegistrar.register()
        _appState.wrappedValue.installNotificationHandling()
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

    /// Reads the setting so a language change republishes `\.locale` in the same update.
    private var resolvedLocale: Locale {
        _ = appState.settings.language
        return AppLocale.locale
    }
}
