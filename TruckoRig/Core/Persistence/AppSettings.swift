import Foundation
import Observation
import WidgetKit

/// Driver preferences, stored in `UserDefaults`.
///
/// Keys are namespaced by store so a one-time Apple→local migration can copy goal and week
/// settings without colliding with a leftover empty local profile.
@Observable
final class AppSettings {

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let widgetDefaults: UserDefaults?
    private(set) var scope: AccountScope

    init(
        scope: AccountScope = .local,
        defaults: UserDefaults = .standard,
        widgetDefaults: UserDefaults? = UserDefaults(suiteName: WidgetBridge.appGroup)
    ) {
        self.defaults = defaults
        self.widgetDefaults = widgetDefaults
        self.scope = scope
        self.weeklyGoal = Self.read(defaults, scope, .weeklyGoal, default: 0)
        self.language = Self.readEnum(defaults, scope, .language, default: .system)
        self.weekStart = Self.readEnum(defaults, scope, .weekStart, default: .sunday)
        self.themeMode = Self.readThemeMode(defaults, scope)
        self.oledDark = Self.read(defaults, scope, .oledDark, default: false)
        self.rpmMinProfit = Self.read(defaults, scope, .rpmMinProfit, default: RPMThresholds.default.minProfit)
        self.rpmTargetProfit = Self.read(defaults, scope, .rpmTargetProfit, default: RPMThresholds.default.targetProfit)
        self.notifyMissingWeek = Self.read(defaults, scope, .notifyMissingWeek, default: true)
        self.notifyMaintenance = Self.read(defaults, scope, .notifyMaintenance, default: true)
        self.quietHoursEnabled = Self.read(defaults, scope, .quietHoursEnabled, default: false)
        self.quietStartHour = Self.read(defaults, scope, .quietStartHour, default: 22)
        self.quietEndHour = Self.read(defaults, scope, .quietEndHour, default: 7)
        let lastRun = Self.read(defaults, scope, .smartNotificationLastRun, default: 0.0)
        self.smartNotificationLastRun = lastRun > 0 ? Date(timeIntervalSince1970: lastRun) : nil
        self.missingNotifiedWeek = Self.read(defaults, scope, .missingNotifiedWeek, default: "")
        self.onboardingComplete = Self.read(defaults, scope, .onboardingComplete, default: false)
        if UITestLaunch.isEnabled {
            self.onboardingComplete = true
        }
        mirrorThemeToWidget(reloadWidget: false)
    }

    // MARK: - Values

    var weeklyGoal: Double { didSet { write(.weeklyGoal, weeklyGoal) } }
    /// Android `app_theme_mode`. Defaults to system.
    var themeMode: AppThemeMode {
        didSet {
            write(.themeMode, themeMode.rawValue)
            mirrorThemeToWidget(reloadWidget: true)
        }
    }
    /// Android `oled_dark`. Kept when Light is selected; applied only while the cabin is dark.
    var oledDark: Bool { didSet { write(.oledDark, oledDark) } }
    var language: AppLanguage { didSet { write(.language, language.rawValue) } }
    var weekStart: WeekStartDay { didSet { write(.weekStart, weekStart.rawValue) } }
    var rpmMinProfit: Double { didSet { write(.rpmMinProfit, rpmMinProfit) } }
    var rpmTargetProfit: Double { didSet { write(.rpmTargetProfit, rpmTargetProfit) } }
    var onboardingComplete: Bool { didSet { write(.onboardingComplete, onboardingComplete) } }

    /// Android `notifyMissingWeek`, default on.
    var notifyMissingWeek: Bool { didSet { write(.notifyMissingWeek, notifyMissingWeek) } }
    /// Android `notifyMaintenance`, default on.
    var notifyMaintenance: Bool { didSet { write(.notifyMaintenance, notifyMaintenance) } }
    var quietHoursEnabled: Bool { didSet { write(.quietHoursEnabled, quietHoursEnabled) } }
    var quietStartHour: Int { didSet { write(.quietStartHour, min(23, max(0, quietStartHour))) } }
    var quietEndHour: Int { didSet { write(.quietEndHour, min(23, max(0, quietEndHour))) } }
    var smartNotificationLastRun: Date? {
        didSet {
            let key = Self.storageKey(scope, .smartNotificationLastRun)
            if let smartNotificationLastRun {
                defaults.set(smartNotificationLastRun.timeIntervalSince1970, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
    /// `year-Wweek` of the previous trucking week already handed to UserNotifications.
    var missingNotifiedWeek: String { didSet { write(.missingNotifiedWeek, missingNotifiedWeek) } }

    // MARK: - Derived

    var rpmThresholds: RPMThresholds {
        RPMThresholds(minProfit: rpmMinProfit, targetProfit: rpmTargetProfit)
    }

    var truckingWeek: TruckingWeek {
        TruckingWeek(weekStart: weekStart)
    }

    var hasStoredThemeMode: Bool {
        defaults.object(forKey: Self.storageKey(scope, .themeMode)) != nil
    }

    var hasStoredOledDark: Bool {
        defaults.object(forKey: Self.storageKey(scope, .oledDark)) != nil
    }

    // MARK: - Storage

    private enum Key: String {
        case weeklyGoal
        case themeMode = "app_theme_mode"
        case oledDark = "oled_dark"
        case language
        case weekStart
        case rpmMinProfit
        case rpmTargetProfit
        case notifyMissingWeek
        case notifyMaintenance
        case quietHoursEnabled
        case quietStartHour
        case quietEndHour
        case smartNotificationLastRun
        case missingNotifiedWeek
        case onboardingComplete
    }

    private static func storageKey(_ scope: AccountScope, _ key: Key) -> String {
        "truckorig.\(scope.storeKey).\(key.rawValue)"
    }

    private func write(_ key: Key, _ value: Any) {
        defaults.set(value, forKey: Self.storageKey(scope, key))
    }

    private static func read<T>(_ defaults: UserDefaults, _ scope: AccountScope, _ key: Key, default fallback: T) -> T {
        defaults.object(forKey: storageKey(scope, key)) as? T ?? fallback
    }

    private static func readThemeMode(_ defaults: UserDefaults, _ scope: AccountScope) -> AppThemeMode {
        guard let raw = defaults.object(forKey: storageKey(scope, .themeMode)) as? Int else { return .system }
        return AppThemeMode.fromOrdinal(raw)
    }

    /// The widget extension cannot see this process's standard defaults, so the ordinal is copied
    /// to the App Group under the Android key. OLED is not copied: the Android widget ignores it.
    private func mirrorThemeToWidget(reloadWidget: Bool) {
        guard let widgetDefaults else { return }
        widgetDefaults.set(themeMode.rawValue, forKey: AppThemeMode.dataStoreKey)
        // Launch republishes the snapshot, which reloads the widget. A later theme change does not.
        if reloadWidget {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.kind)
        }
    }

    private static func readEnum<T: RawRepresentable>(
        _ defaults: UserDefaults,
        _ scope: AccountScope,
        _ key: Key,
        default fallback: T
    ) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: storageKey(scope, key)) else { return fallback }
        return T(rawValue: raw) ?? fallback
    }
}
