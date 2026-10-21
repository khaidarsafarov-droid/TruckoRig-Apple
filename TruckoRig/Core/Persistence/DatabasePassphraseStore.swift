import Foundation
import Security

enum DatabasePassphraseError: Error, CustomStringConvertible {
    case randomFailed(OSStatus)
    case keychainFailed(OSStatus)

    var description: String {
        switch self {
        case .randomFailed(let status):
            return "Could not generate a database passphrase (\(status))."
        case .keychainFailed(let status):
            return "Could not read the database passphrase from the Keychain (\(status))."
        }
    }
}

/// 256-bit SQLCipher passphrase.
///
/// Android keeps the same 32 bytes wrapped by a Keystore AES-GCM key (`DatabasePassphraseStore`).
/// The iOS Keychain is already the device-bound wrapper, so the passphrase itself is the Keychain
/// item. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` matches a database the widget may
/// read later, and the item does not leave this phone in a backup.
struct DatabasePassphraseStore {
    static let byteCount = 32
    static let service = "com.truckorig.database-passphrase"
    static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    var account: String

    func getOrCreate() throws -> Data {
        if let existing = try read() {
            return existing
        }
        let created = try Self.randomBytes()
        try write(created)
        return created
    }

    func read() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DatabasePassphraseError.keychainFailed(status) }
        return item as? Data
    }

    func write(_ passphrase: Data) throws {
        var query = baseQuery()
        query[kSecValueData as String] = passphrase
        query[kSecAttrAccessible as String] = Self.accessibility
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: passphrase]
            let updated = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
            guard updated == errSecSuccess else { throw DatabasePassphraseError.keychainFailed(updated) }
            return
        }
        guard status == errSecSuccess else { throw DatabasePassphraseError.keychainFailed(status) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DatabasePassphraseError.keychainFailed(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }

    static func randomBytes() throws -> Data {
        var data = Data(count: byteCount)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, byteCount, address)
        }
        guard status == errSecSuccess else { throw DatabasePassphraseError.randomFailed(status) }
        return data
    }
}
