import Foundation
import Observation

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

/// The driver and their truck. Exactly one row per account.
@Observable
final class DriverProfile: Identifiable {
    var id: UUID
    /// First and last name, stored as one string.
    var name: String?
    var truckModel: String?
    var truckYear: Int?
    var licensePlate: String?
    var homeState: String?
    var preferredLanguage: AppLanguage
    var weeklyGoal: Double
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String? = nil,
        truckModel: String? = nil,
        truckYear: Int? = nil,
        licensePlate: String? = nil,
        homeState: String? = nil,
        preferredLanguage: AppLanguage = .system,
        weeklyGoal: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.truckModel = truckModel
        self.truckYear = truckYear
        self.licensePlate = licensePlate
        self.homeState = homeState
        self.preferredLanguage = preferredLanguage
        self.weeklyGoal = weeklyGoal
        self.updatedAt = updatedAt
    }

    /// Splits a stored `"First Last"` name. A single word stays the given name.
    var givenAndFamilyName: (given: String, family: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let space = trimmed.firstIndex(of: " ") else { return (given: trimmed, family: "") }
        let givenName = String(trimmed[..<space])
        let familyName = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return (given: givenName, family: familyName)
    }

    static func fullName(given: String, family: String) -> String? {
        [given, family]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nonEmpty
    }

    var truckDescription: String {
        let parts = [truckYear.map(String.init), truckModel].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}
