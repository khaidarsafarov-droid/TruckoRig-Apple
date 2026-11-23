import SwiftUI

@main
struct TruckoRigApp: App {

    @State private var appState: AppState?

    init() {
        AppLocale.install()
        TelegramBackgroundRegistrar.register()
        ICloudBackgroundRegistrar.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let appState {
                    RootView()
                        .environment(appState)
                        .tint(.forestPrimary)
                        .modifier(AppCabinTheme(
                            mode: appState.settings.themeMode,
                            oledDark: appState.settings.oledDark,
                            reduceMotion: appState.settings.reduceMotion
                        ))
                        .environment(\.locale, locale(for: appState))
                } else {
                    Color.clear
                        .forestBackground()
                }
            }
            .task {
                guard appState == nil else { return }
                let state = AppState()
                state.prepareJournal()
                appState = state
                state.bootstrap()
            }
        }
    }

    /// Reads the setting so a language change republishes `\.locale` in the same update.
    private func locale(for appState: AppState) -> Locale {
        _ = appState.settings.language
        return AppLocale.locale
    }
}
