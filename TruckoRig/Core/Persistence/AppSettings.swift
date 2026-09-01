import Foundation
import Observation

/// Driver preferences, stored in `UserDefaults` and scoped per account.
///
/// Keys are namespaced by account so two drivers sharing a phone do not inherit each other's goal,
/// week start or backend URL. Nothing secret lives here — tokens go to the Keychain.
///
/// Each setting is a computed property over a cached value rather than a stored one with a
/// `didSet`: `@Observable` cannot transform properties that already have observers, and the
/// explicit `access`/`withMutation` pair is what makes a write both persist and refresh the UI.
@Observable
final class AppSettings {

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cache: Values
    private(set) var scope: AccountScope

    init(scope: AccountScope = .local, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.scope = scope
        self.cache = Values(defaults: defaults, scope: scope)
    }

    // MARK: - Values

    var weeklyGoal: Double {
        get { access(keyPath: \.weeklyGoal); return cache.weeklyGoal }
        set { withMutation(keyPath: \.weeklyGoal) { cache.weeklyGoal = newValue; write(.weeklyGoal, newValue) } }
    }

    var language: AppLanguage {
        get { access(keyPath: \.language); return cache.language }
        set { withMutation(keyPath: \.language) { cache.language = newValue; write(.language, newValue.rawValue) } }
    }

    var weekStart: WeekStartDay {
        get { access(keyPath: \.weekStart); return cache.weekStart }
        set { withMutation(keyPath: \.weekStart) { cache.weekStart = newValue; write(.weekStart, newValue.rawValue) } }
    }

    var isCloudSyncEnabled: Bool {
        get { access(keyPath: \.isCloudSyncEnabled); return cache.isCloudSyncEnabled }
        set {
            withMutation(keyPath: \.isCloudSyncEnabled) {
                cache.isCloudSyncEnabled = newValue
                write(.cloudSyncEnabled, newValue)
            }
        }
    }

    var syncBackendURL: String {
        get { access(keyPath: \.syncBackendURL); return cache.syncBackendURL }
        set {
            withMutation(keyPath: \.syncBackendURL) {
                cache.syncBackendURL = newValue
                write(.syncBackendURL, newValue)
            }
        }
    }

    var rpmMinProfit: Double {
        get { access(keyPath: \.rpmMinProfit); return cache.rpmMinProfit }
        set { withMutation(keyPath: \.rpmMinProfit) { cache.rpmMinProfit = newValue; write(.rpmMinProfit, newValue) } }
    }

    var rpmTargetProfit: Double {
        get { access(keyPath: \.rpmTargetProfit); return cache.rpmTargetProfit }
        set {
            withMutation(keyPath: \.rpmTargetProfit) {
                cache.rpmTargetProfit = newValue
                write(.rpmTargetProfit, newValue)
            }
        }
    }

    var hasCompletedWelcome: Bool {
        get { access(keyPath: \.hasCompletedWelcome); return cache.hasCompletedWelcome }
        set {
            withMutation(keyPath: \.hasCompletedWelcome) {
                cache.hasCompletedWelcome = newValue
                write(.hasCompletedWelcome, newValue)
            }
        }
    }

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
        let values = Values(defaults: defaults, scope: scope)
        // Assigning through the setters keeps observers notified; the writes are no-ops because
        // the values came from that account's own storage.
        weeklyGoal = values.weeklyGoal
        language = values.language
        weekStart = values.weekStart
        isCloudSyncEnabled = values.isCloudSyncEnabled
        syncBackendURL = values.syncBackendURL
        rpmMinProfit = values.rpmMinProfit
        rpmTargetProfit = values.rpmTargetProfit
        hasCompletedWelcome = values.hasCompletedWelcome
    }

    // MARK: - Storage

    private struct Values {
        var weeklyGoal: Double
        var language: AppLanguage
        var weekStart: WeekStartDay
        var isCloudSyncEnabled: Bool
        var syncBackendURL: String
        var rpmMinProfit: Double
        var rpmTargetProfit: Double
        var hasCompletedWelcome: Bool

        init(defaults: UserDefaults, scope: AccountScope) {
            func read<T>(_ key: Key, _ fallback: T) -> T {
                defaults.object(forKey: AppSettings.storageKey(scope, key)) as? T ?? fallback
            }
            func readEnum<T: RawRepresentable>(_ key: Key, _ fallback: T) -> T where T.RawValue == String {
                guard let raw = defaults.string(forKey: AppSettings.storageKey(scope, key)) else { return fallback }
                return T(rawValue: raw) ?? fallback
            }

            weeklyGoal = read(.weeklyGoal, 0)
            language = readEnum(.language, .system)
            weekStart = readEnum(.weekStart, .sunday)
            isCloudSyncEnabled = read(.cloudSyncEnabled, false)
            syncBackendURL = read(.syncBackendURL, "")
            rpmMinProfit = read(.rpmMinProfit, RPMThresholds.default.minProfit)
            rpmTargetProfit = read(.rpmTargetProfit, RPMThresholds.default.targetProfit)
            hasCompletedWelcome = read(.hasCompletedWelcome, false)
        }
    }

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
}
