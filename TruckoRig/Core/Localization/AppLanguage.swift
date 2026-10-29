import Foundation

/// UI language. `.system` follows the device setting.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case russian
    case english
    case french
    case spanish

    var id: String { rawValue }

    /// BCP-47 tag to force, or `nil` to follow the device.
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .russian: return "ru"
        case .english: return "en"
        case .french: return "fr"
        case .spanish: return "es"
        }
    }

    var displayName: String {
        switch self {
        case .system: return String(localized: "settings.language.system")
        case .russian: return "Русский"
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        }
    }
}
