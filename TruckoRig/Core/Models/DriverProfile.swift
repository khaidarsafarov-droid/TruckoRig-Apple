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
    var name: String?
    var carrier: String?
    var truckModel: String?
    var truckYear: Int?
    var licensePlate: String?
    var homeState: String?
    /// `ownerOperator`, `hiredDriver` or `dispatcher`. Empty until onboarding picks one.
    var role: String?
    var cdlNumber: String?
    var experienceYears: Int?
    var phoneNumber: String?
    var telegramUsername: String?
    var avatarFileName: String?
    var preferredLanguage: AppLanguage
    var weeklyGoal: Double
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String? = nil,
        carrier: String? = nil,
        truckModel: String? = nil,
        truckYear: Int? = nil,
        licensePlate: String? = nil,
        homeState: String? = nil,
        role: String? = nil,
        cdlNumber: String? = nil,
        experienceYears: Int? = nil,
        phoneNumber: String? = nil,
        telegramUsername: String? = nil,
        avatarFileName: String? = nil,
        preferredLanguage: AppLanguage = .system,
        weeklyGoal: Double = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.carrier = carrier
        self.truckModel = truckModel
        self.truckYear = truckYear
        self.licensePlate = licensePlate
        self.homeState = homeState
        self.role = role
        self.cdlNumber = cdlNumber
        self.experienceYears = experienceYears
        self.phoneNumber = phoneNumber
        self.telegramUsername = telegramUsername
        self.avatarFileName = avatarFileName
        self.preferredLanguage = preferredLanguage
        self.weeklyGoal = weeklyGoal
        self.updatedAt = updatedAt
    }

    var truckDescription: String {
        let parts = [truckYear.map(String.init), truckModel].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }
}
