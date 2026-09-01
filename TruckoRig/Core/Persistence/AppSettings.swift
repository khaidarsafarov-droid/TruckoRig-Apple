import Foundation
import Observation

/// Driver preferences, stored in `UserDefaults` and scoped per account.
///
/// Keys are namespaced by account so two drivers sharing a phone do not inherit each other's goal,
/// week start or backend URL. Nothing secret lives here — tokens go to the Keychain.
@Observable
final class AppSettings {

    private let defaults: UserDefaults
    private(set) var scope: AccountScope

    init(scope: AccountScope = .local, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.scope = scope
        self.weeklyGoal = Self.read(defaults, scope, .weeklyGoal, default: 0)
        self.language = Self.readEnum(defaults, scope, .language, default: .system)
        self.weekStart = Self.readEnum(defaults, scope, .weekStart, default: .sunday)
        self.isCloudSyncEnabled = Self.read(defaults, scope, .cloudSyncEnabled, default: false)
        self.syncBackendURL = Self.read(defaults, scope, .syncBackendURL, default: "")
        self.rpmMinProfit = Self.read(defaults, scope, .rpmMinProfit, default: RPMThresholds.default.minProfit)
        self.rpmTargetProfit = Self.read(defaults, scope, .rpmTargetProfit, default: RPMThresholds.default.targetProfit)
        self.hasCompletedWelcome = Self.read(defaults, scope, .hasCompletedWelcome, default: false)
    }

    // MARK: - Values

    var weeklyGoal: Double { didSet { write(.weeklyGoal, weeklyGoal) } }
    var language: AppLanguage { didSet { write(.language, language.rawValue) } }
    var weekStart: WeekStartDay { didSet { write(.weekStart, weekStart.rawValue) } }
    var isCloudSyncEnabled: Bool { didSet { write(.cloudSyncEnabled, isCloudSyncEnabled) } }
    var syncBackendURL: String { didSet { write(.syncBackendURL, syncBackendURL) } }
    var rpmMinProfit: Double { didSet { write(.rpmMinProfit, rpmMinProfit) } }
    var rpmTargetProfit: Double { didSet { write(.rpmTargetProfit, rpmTargetProfit) } }
    var hasCompletedWelcome: Bool { didSet { write(.hasCompletedWelcome, hasCompletedWelcome) } }

    // MARK: - Derived

    var rpmThresholds: RPMThresholds {
        RPMThresholds(minProfit: rpmMinProfit, targetProfit: rpmTargetProfit)
    }

    var truckingWeek: TruckingWeek {
        TruckingWeek(weekStart: weekStart)
    }

    /// Backend base URL, or `nil` when sync is off or the URL is unusable.
    var resolvedBackendURL: URL? {
        guard isCloudSyncEnabled else { return nil }
        guard let url = URL(string: syncBackendURL.trimmed), url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    /// Re-reads every value for a different account.
    func rebind(to scope: AccountScope) {
        guard scope != self.scope else { return }
        self.scope = scope
        weeklyGoal = Self.read(defaults, scope, .weeklyGoal, default: 0)
        language = Self.readEnum(defaults, scope, .language, default: .system)
        weekStart = Self.readEnum(defaults, scope, .weekStart, default: .sunday)
        isCloudSyncEnabled = Self.read(defaults, scope, .cloudSyncEnabled, default: false)
        syncBackendURL = Self.read(defaults, scope, .syncBackendURL, default: "")
        rpmMinProfit = Self.read(defaults, scope, .rpmMinProfit, default: RPMThresholds.default.minProfit)
        rpmTargetProfit = Self.read(defaults, scope, .rpmTargetProfit, default: RPMThresholds.default.targetProfit)
        hasCompletedWelcome = Self.read(defaults, scope, .hasCompletedWelcome, default: false)
    }

    // MARK: - Storage

    private enum Key: String {
        case weeklyGoal
        case language
        case weekStart
        case cloudSyncEnabled
        case syncBackendURL
        case rpmMinProfit
        case rpmTargetProfit
        case hasCompletedWelcome
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
