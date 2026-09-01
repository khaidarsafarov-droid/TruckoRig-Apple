import Foundation
import Security

/// Credentials for one signed-in account.
struct AuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?

    /// Treats a token as expired a minute early so a request never leaves with a token that dies
    /// in flight.
    func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.addingTimeInterval(-60) <= now
    }
}

/// Keychain-backed token storage.
///
/// Tokens never touch `UserDefaults` or the app's log. Items are stored with
/// `kSecAttrAccessibleAfterFirstUnlock` so background sync still works while the phone is locked
/// in a cradle, but nothing is readable before the first unlock after a reboot.
enum JWTStore {

    static let service = "com.truckorig.jwt"

    static func save(_ tokens: AuthTokens, for userId: String) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        var query = baseQuery(userId: userId)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            AppLog.auth.error("Keychain write failed with status \(status, privacy: .public)")
        }
    }

    static func load(for userId: String) -> AuthTokens? {
        var query = baseQuery(userId: userId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }

    static func delete(for userId: String) {
        SecItemDelete(baseQuery(userId: userId) as CFDictionary)
    }

    /// Clears every account's tokens. Used when the driver erases local data.
    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func baseQuery(userId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userId,
        ]
    }
}
