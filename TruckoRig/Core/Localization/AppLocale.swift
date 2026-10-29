import Foundation
import ObjectiveC

/// The one language the interface uses. `String(localized:)` and date formatters read it,
/// and the root view publishes the same value as `\.locale`.
enum AppLocale {
    static let appGroupSuite = "group.com.truckorig"
    static let storageKey = "truckorig.language"

    private static let lock = NSLock()
    private static var overrideBundle: Bundle?
    private static var active = Locale.current
    private static var installed = false

    /// Points `Bundle.main` string lookup at the selected language. Safe to call more than once.
    static func install() {
        lock.lock()
        let already = installed
        installed = true
        lock.unlock()
        guard !already else { return }
        object_setClass(Bundle.main, LocalizedLookup.self)
    }

    static func apply(_ language: AppLanguage) {
        let code = resolvedCode(for: language)
        let bundle: Bundle?
        if language == .system {
            bundle = nil
        } else {
            bundle = lproj(code)
        }
        lock.lock()
        overrideBundle = bundle
        active = language == .system ? .current : Locale(identifier: code)
        lock.unlock()
        publish(code: language == .system ? "" : code)
    }

    /// Widget process: follow the code the app wrote into the App Group.
    static func applyStoredWidgetLanguage() {
        let stored = UserDefaults(suiteName: appGroupSuite)?.string(forKey: storageKey) ?? ""
        guard !stored.isEmpty else {
            lock.lock()
            overrideBundle = nil
            active = .current
            lock.unlock()
            return
        }
        lock.lock()
        overrideBundle = lproj(stored)
        active = Locale(identifier: stored)
        lock.unlock()
    }

    static var locale: Locale {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    static func resolvedCode(for language: AppLanguage) -> String {
        if let identifier = language.localeIdentifier { return identifier }
        let preferred = Locale.preferredLanguages.first ?? "en"
        let code = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        return ["en", "ru", "es", "fr"].contains(code) ? code : "en"
    }

    fileprivate static func currentOverride() -> Bundle? {
        lock.lock()
        defer { lock.unlock() }
        return overrideBundle
    }

    private static func lproj(_ code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    private static func publish(code: String) {
        UserDefaults(suiteName: appGroupSuite)?.set(code, forKey: storageKey)
    }
}

/// Substituted for `Bundle.main` so every `String(localized:)` follows `AppLocale`.
private final class LocalizedLookup: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = AppLocale.currentOverride() {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
