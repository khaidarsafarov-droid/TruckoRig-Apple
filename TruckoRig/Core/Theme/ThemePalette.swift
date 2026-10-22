import Foundation
import SwiftUI

/// Android `AppThemeMode`. Ordinals match `SettingsDataStore` key `app_theme_mode`.
enum AppThemeMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    /// Android DataStore key `app_theme_mode`.
    static let dataStoreKey = "app_theme_mode"
    /// Android DataStore key `oled_dark`.
    static let oledDataStoreKey = "oled_dark"

    var id: Int { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "settings.theme.system"
        case .light: return "settings.theme.light"
        case .dark: return "settings.theme.dark"
        }
    }

    /// `nil` follows the device, the same as `MODE_NIGHT_FOLLOW_SYSTEM`.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Android shows the OLED row for Dark and System, and hides it for Light.
    var showsOledToggle: Bool { self != .light }

    static func fromOrdinal(_ ordinal: Int) -> AppThemeMode {
        AppThemeMode(rawValue: ordinal) ?? .system
    }

    /// WidgetKit follows the saved app theme. Android `WidgetCabinColors.resolve` does the same
    /// and does not read `oled_dark`, so this returns only light, dark, or system.
    static func widgetColorScheme(
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetBridge.appGroup)
    ) -> ColorScheme? {
        guard let defaults, defaults.object(forKey: dataStoreKey) != nil else { return nil }
        return fromOrdinal(defaults.integer(forKey: dataStoreKey)).preferredColorScheme
    }
}

/// Midnight & Gold surfaces from Android `SoftUiColors`, plus the OLED override in `overlayOledIfNeeded`.
///
/// OLED replaces the page, card, and muted surfaces only. Accents stay champagne gold in the dark
/// cabin and indigo in the light cabin.
enum ThemePalette {
    static let backgroundLight = "F5F4F1"
    static let backgroundDark = "0D0F1E"
    static let backgroundOled = "000000"

    static let surfaceLight = "FDFCFA"
    static let surfaceDark = "161929"
    static let surfaceOled = "121212"

    static let surfaceMutedLight = "EAE9F4"
    static let surfaceMutedDark = "262A4F"
    static let surfaceMutedOled = "1C1C1C"

    static let accentLight = "3F3D9E"
    static let accentDark = "D6BC85"

    static func isDark(mode: AppThemeMode, systemIsDark: Bool) -> Bool {
        switch mode {
        case .light: return false
        case .dark: return true
        case .system: return systemIsDark
        }
    }

    /// Android applies OLED only when the resolved theme is dark: `oledDark && darkTheme`.
    static func oledApplies(mode: AppThemeMode, oledDark: Bool, systemIsDark: Bool) -> Bool {
        oledDark && isDark(mode: mode, systemIsDark: systemIsDark)
    }

    static func background(dark: Bool, oled: Bool) -> String {
        guard dark else { return backgroundLight }
        return oled ? backgroundOled : backgroundDark
    }

    static func surface(dark: Bool, oled: Bool) -> String {
        guard dark else { return surfaceLight }
        return oled ? surfaceOled : surfaceDark
    }

    static func surfaceMuted(dark: Bool, oled: Bool) -> String {
        guard dark else { return surfaceMutedLight }
        return oled ? surfaceMutedOled : surfaceMutedDark
    }

    /// Gold in the dark cabin, indigo in the light cabin. OLED does not recolor it.
    static func accent(dark: Bool) -> String {
        dark ? accentDark : accentLight
    }
}
