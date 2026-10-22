import Foundation
import Security

enum TelegramTokenStoreError: Error {
    case keychain(OSStatus)
}

/// The BotFather token. It is entered by the driver and never written to the repo, logs, or a backup.
struct TelegramTokenStore {
    static let service = "com.truckorig.telegram-bot-token"
    static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    var account: String

    func read() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw TelegramTokenStoreError.keychain(status) }
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }

    func write(_ token: String) throws {
        let data = Data(TelegramTokenRules.normalized(token).utf8)
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = Self.accessibility
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updated = SecItemUpdate(baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard updated == errSecSuccess else { throw TelegramTokenStoreError.keychain(updated) }
            return
        }
        guard status == errSecSuccess else { throw TelegramTokenStoreError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TelegramTokenStoreError.keychain(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }
}
