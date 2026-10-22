import SwiftUI
import UIKit
import XCTest
@testable import TruckoRig

/// Theme choice survives a relaunch, and OLED swaps only the dark surfaces.
final class ThemeSettingsTests: XCTestCase {

    private var suiteName = ""
    private var widgetSuiteName = ""
    private var defaults: UserDefaults!
    private var widgetDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "theme-\(UUID().uuidString)"
        widgetSuiteName = "theme-widget-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        widgetDefaults = UserDefaults(suiteName: widgetSuiteName)
        defaults.removePersistentDomain(forName: suiteName)
        widgetDefaults.removePersistentDomain(forName: widgetSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        widgetDefaults.removePersistentDomain(forName: widgetSuiteName)
        super.tearDown()
    }

    func testThemeModeAndOledRoundTripThroughUserDefaults() {
        let settings = makeSettings()
        XCTAssertEqual(settings.themeMode, .system)
        XCTAssertFalse(settings.oledDark)
        XCTAssertFalse(settings.hasStoredThemeMode)
        XCTAssertEqual(widgetDefaults.object(forKey: AppThemeMode.dataStoreKey) as? Int, AppThemeMode.system.rawValue)

        settings.themeMode = .dark
        settings.oledDark = true
        settings.themeMode = .light
        XCTAssertTrue(settings.oledDark, "Light hides the OLED row but keeps the saved flag")

        let reloaded = makeSettings()
        XCTAssertEqual(reloaded.themeMode, .light)
        XCTAssertTrue(reloaded.oledDark)
        XCTAssertEqual(defaults.object(forKey: "truckorig.local.\(AppThemeMode.dataStoreKey)") as? Int, AppThemeMode.light.rawValue)
        XCTAssertEqual(defaults.object(forKey: "truckorig.local.\(AppThemeMode.oledDataStoreKey)") as? Bool, true)
        XCTAssertEqual(widgetDefaults.object(forKey: AppThemeMode.dataStoreKey) as? Int, AppThemeMode.light.rawValue)
        XCTAssertNil(widgetDefaults.object(forKey: AppThemeMode.oledDataStoreKey))

        reloaded.themeMode = .system
        reloaded.oledDark = false
        let system = makeSettings()
        XCTAssertEqual(system.themeMode, .system)
        XCTAssertFalse(system.oledDark)
        XCTAssertEqual(widgetDefaults.object(forKey: AppThemeMode.dataStoreKey) as? Int, AppThemeMode.system.rawValue)
    }

    func testUnknownThemeOrdinalFallsBackToSystem() {
        defaults.set(42, forKey: "truckorig.local.\(AppThemeMode.dataStoreKey)")
        let settings = makeSettings()
        XCTAssertEqual(settings.themeMode, .system)
        XCTAssertEqual(AppThemeMode.fromOrdinal(0), .system)
        XCTAssertEqual(AppThemeMode.fromOrdinal(1), .light)
        XCTAssertEqual(AppThemeMode.fromOrdinal(2), .dark)
        XCTAssertEqual(AppThemeMode.allCases.map(\.rawValue), [0, 1, 2])
    }

    func testWidgetSchemeFollowsAppThemeAndIgnoresOled() {
        XCTAssertNil(AppThemeMode.widgetColorScheme(defaults: widgetDefaults))
        widgetDefaults.set(true, forKey: AppThemeMode.oledDataStoreKey)
        XCTAssertNil(AppThemeMode.widgetColorScheme(defaults: widgetDefaults))

        widgetDefaults.set(AppThemeMode.dark.rawValue, forKey: AppThemeMode.dataStoreKey)
        XCTAssertEqual(AppThemeMode.widgetColorScheme(defaults: widgetDefaults), .dark)
        widgetDefaults.set(AppThemeMode.light.rawValue, forKey: AppThemeMode.dataStoreKey)
        XCTAssertEqual(AppThemeMode.widgetColorScheme(defaults: widgetDefaults), .light)
        widgetDefaults.set(AppThemeMode.system.rawValue, forKey: AppThemeMode.dataStoreKey)
        XCTAssertNil(AppThemeMode.widgetColorScheme(defaults: widgetDefaults))
        widgetDefaults.set(9, forKey: AppThemeMode.dataStoreKey)
        XCTAssertNil(AppThemeMode.widgetColorScheme(defaults: widgetDefaults))
    }

    func testPaletteSelectionMatchesAndroidOledAndMidnightGold() {
        XCTAssertEqual(ThemePalette.background(dark: false, oled: false), "F5F4F1")
        XCTAssertEqual(ThemePalette.surface(dark: false, oled: false), "FDFCFA")
        XCTAssertEqual(ThemePalette.surfaceMuted(dark: false, oled: false), "EAE9F4")
        XCTAssertEqual(ThemePalette.accent(dark: false), "3F3D9E")

        XCTAssertEqual(ThemePalette.background(dark: true, oled: false), "0D0F1E")
        XCTAssertEqual(ThemePalette.surface(dark: true, oled: false), "161929")
        XCTAssertEqual(ThemePalette.surfaceMuted(dark: true, oled: false), "262A4F")
        XCTAssertEqual(ThemePalette.accent(dark: true), "D6BC85")

        XCTAssertEqual(ThemePalette.background(dark: true, oled: true), "000000")
        XCTAssertEqual(ThemePalette.surface(dark: true, oled: true), "121212")
        XCTAssertEqual(ThemePalette.surfaceMuted(dark: true, oled: true), "1C1C1C")
        XCTAssertEqual(ThemePalette.accent(dark: true), "D6BC85")
        XCTAssertEqual(ThemePalette.background(dark: false, oled: true), "F5F4F1")
        XCTAssertEqual(ThemePalette.accent(dark: false), "3F3D9E")

        XCTAssertFalse(AppThemeMode.light.showsOledToggle)
        XCTAssertTrue(AppThemeMode.dark.showsOledToggle)
        XCTAssertTrue(AppThemeMode.system.showsOledToggle)
        XCTAssertTrue(ThemePalette.oledApplies(mode: .dark, oledDark: true, systemIsDark: false))
        XCTAssertTrue(ThemePalette.oledApplies(mode: .system, oledDark: true, systemIsDark: true))
        XCTAssertFalse(ThemePalette.oledApplies(mode: .system, oledDark: true, systemIsDark: false))
        XCTAssertFalse(ThemePalette.oledApplies(mode: .light, oledDark: true, systemIsDark: true))
        XCTAssertFalse(ThemePalette.oledApplies(mode: .dark, oledDark: false, systemIsDark: true))
    }

    func testResolvedColorsKeepGoldAndSwapOledSurfaces() {
        let light = traits(.light, oled: false)
        let lightOled = traits(.light, oled: true)
        let dark = traits(.dark, oled: false)
        let oled = traits(.dark, oled: true)

        let accent = CabinUIColors.adaptive(light: ThemePalette.accentLight, dark: ThemePalette.accentDark, oled: nil)
        let onAccent = CabinUIColors.adaptive(light: "FFFFFF", dark: "1D1708", oled: nil)
        let gold = CabinUIColors.adaptive(light: "C8A867", dark: "D6BC85", oled: nil)

        XCTAssertEqual(hex(CabinUIColors.background, light), ThemePalette.backgroundLight)
        XCTAssertEqual(hex(CabinUIColors.card, light), ThemePalette.surfaceLight)
        XCTAssertEqual(hex(CabinUIColors.muted, light), ThemePalette.surfaceMutedLight)
        XCTAssertEqual(hex(accent, light), ThemePalette.accentLight)

        XCTAssertEqual(hex(CabinUIColors.background, lightOled), ThemePalette.backgroundLight)
        XCTAssertEqual(hex(accent, lightOled), ThemePalette.accentLight)

        XCTAssertEqual(hex(CabinUIColors.background, dark), ThemePalette.backgroundDark)
        XCTAssertEqual(hex(CabinUIColors.card, dark), ThemePalette.surfaceDark)
        XCTAssertEqual(hex(CabinUIColors.muted, dark), ThemePalette.surfaceMutedDark)
        XCTAssertEqual(hex(accent, dark), ThemePalette.accentDark)
        XCTAssertEqual(hex(onAccent, dark), "1D1708")

        XCTAssertEqual(hex(CabinUIColors.background, oled), ThemePalette.backgroundOled)
        XCTAssertEqual(hex(CabinUIColors.card, oled), ThemePalette.surfaceOled)
        XCTAssertEqual(hex(CabinUIColors.muted, oled), ThemePalette.surfaceMutedOled)
        XCTAssertEqual(hex(accent, oled), ThemePalette.accentDark)
        XCTAssertEqual(hex(onAccent, oled), "1D1708")
        XCTAssertEqual(hex(gold, oled), "D6BC85")
    }

    func testDriveBackupRestoresThemeModeAndOled() throws {
        let database = try AppDatabase.ephemeral()
        let settings = makeSettings()
        let identity = DriveIdentityStore(defaults: defaults)
        var extra = DriveSettingsExtra(themeModeOrdinal: 2, oledDark: true)
        DriveJournalMapper.adoptStoredThemeIfNeeded(settings, extra: &extra)
        XCTAssertEqual(settings.themeMode, .dark)
        XCTAssertTrue(settings.oledDark)

        let exported = DriveJournalMapper.export(
            graph: try database.fetchGraph(),
            settings: settings,
            identity: identity,
            accountId: DriveAccount.localDev,
            exportedAt: 1
        )
        XCTAssertEqual(exported.appSettings?.themeModeOrdinal, 2)
        XCTAssertEqual(exported.appSettings?.oledDark, true)

        let fresh = makeSettings()
        fresh.themeMode = .light
        fresh.oledDark = false
        let json = #"{"schemaVersion":2,"version":2,"accountId":"local_dev","loads":[],"appSettings":{"themeModeOrdinal":1,"oledDark":true}}"#
        let backup = try DriveBackupCodec.decode(json)
        _ = DriveJournalMapper.importBackup(backup, settings: fresh, identity: identity)
        XCTAssertEqual(fresh.themeMode, .light)
        XCTAssertTrue(fresh.oledDark)
        XCTAssertEqual(makeSettings().themeMode, .light)
        XCTAssertTrue(makeSettings().oledDark)
    }

    private func makeSettings() -> AppSettings {
        AppSettings(scope: .local, defaults: defaults, widgetDefaults: widgetDefaults)
    }

    private func traits(_ style: UIUserInterfaceStyle, oled: Bool) -> UITraitCollection {
        UITraitCollection { mutable in
            mutable.userInterfaceStyle = style
            mutable[OLEDDarkTrait.self] = oled
        }
    }

    private func hex(_ color: UIColor, _ traits: UITraitCollection) -> String {
        let resolved = color.resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}
