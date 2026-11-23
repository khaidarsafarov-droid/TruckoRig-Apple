import CryptoKit
import Foundation
import Security

/// Encrypts the share-sheet inbox that the app and the share extension both read.
///
/// The key is a Keychain item in the access group `group.com.truckorig`. Apple lets apps that
/// already share an App Group use that group name as a keychain access group, so this does not
/// add a separate Keychain Sharing capability. The item is
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: the inbox never moves to another phone,
/// and a backup must not contain the key that would unlock a leftover inbox file.
///
/// Sealed bytes start with `TRIN1`. Older plaintext inbox files still open, then the next write
/// replaces them.
enum ShareInboxCrypto {
    static let magic = Data("TRIN1".utf8)
    static let accessGroup = "group.com.truckorig"
    static let service = "com.truckorig.share-inbox-key"
    static let account = "inbox"
    static var testingKey: Data?

    enum Failure: Error {
        case keychain(OSStatus)
        case seal
    }

    static func install() {
        ShareInboxCodec.seal = { try seal($0) }
        ShareInboxCodec.open = { try open($0) }
    }

    static func seal(_ plain: Data) throws -> Data {
        if plain.starts(with: magic) { return plain }
        let key = try symmetricKey()
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else { throw Failure.seal }
        return magic + combined
    }

    static func open(_ data: Data) throws -> Data {
        guard data.starts(with: magic) else { return data }
        let key = try symmetricKey()
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
        return try AES.GCM.open(box, using: key)
    }

    private static func symmetricKey() throws -> SymmetricKey {
        if let testingKey, testingKey.count == 32 {
            return SymmetricKey(data: testingKey)
        }
        if let existing = try readKey() {
            return SymmetricKey(data: existing)
        }
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, 32, address)
        }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        try writeKey(bytes)
        return SymmetricKey(data: bytes)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    private static func readKey() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            throw Failure.keychain(status)
        }
        return data
    }

    private static func writeKey(_ data: Data) throws {
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw Failure.keychain(status)
        }
    }
}
