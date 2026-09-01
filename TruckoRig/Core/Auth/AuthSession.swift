import Foundation

enum AuthProvider: String, Codable, CaseIterable {
    case apple
    case email
    /// Signed-in-free mode: everything stays on the device.
    case local
}

/// The signed-in identity. Tokens live in the Keychain, not here.
struct AuthSession: Codable, Equatable, Identifiable {
    var userId: String
    var provider: AuthProvider
    var email: String?
    var displayName: String?
    var createdAt: Date

    var id: String { userId }

    var scope: AccountScope {
        provider == .local ? .local : .user(userId)
    }

    /// Best label for the profile header.
    var displayLabel: String {
        displayName?.nonEmpty ?? email?.nonEmpty ?? String(localized: "auth.localDriver")
    }

    static let localSession = AuthSession(
        userId: "local",
        provider: .local,
        email: nil,
        displayName: nil,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

/// Persisted pointer to the last signed-in account, so relaunch restores it without a round trip.
enum AuthSessionStore {
    private static let key = "truckorig.session"

    static func save(_ session: AuthSession?, defaults: UserDefaults = .standard) {
        guard let session, let data = try? JSONEncoder().encode(session) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    static func load(defaults: UserDefaults = .standard) -> AuthSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
}
