import CryptoKit
import Foundation
import Security

/// Encrypts journal JSON, the media manifest, and photo or scan bytes before they are written
/// to the iCloud Drive container.
///
/// Format: the ASCII prefix `TRBK1`, then a CryptoKit AES-GCM combined box (nonce, ciphertext, tag).
/// A file that does not start with `TRBK1` is an older plaintext backup. `open` returns those
/// bytes unchanged so a restore still works. The next upload writes the sealed form and replaces
/// the plaintext file.
///
/// The 256-bit key lives in the Keychain as a synchronizable item with
/// `kSecAttrAccessibleAfterFirstUnlock`. Apple does not allow `ThisDeviceOnly` on a synchronizable
/// item. iCloud Keychain copies the key to the driver's other devices, which is what makes a
/// sealed backup restorable there. The key is not written next to the file. If iCloud Keychain
/// is off, the sealed file can be read on this phone only; an older plaintext file still restores.
///
/// Unit tests set `testingKey` so an unsigned simulator, which has no keychain entitlement, can
/// still round-trip a sealed file. Production leaves it nil.
enum CloudPayloadSealer {
    static let magic = Data("TRBK1".utf8)
    static let service = "com.truckorig.icloud-payload-key"
    static let account = "backup"
    static var testingKey: Data?

    enum Failure: Error {
        case keychain(OSStatus)
        case seal
    }

    static func seal(_ plain: Data) throws -> Data {
        if plain.starts(with: magic) { return plain }
        let key = try symmetricKey()
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else { throw Failure.seal }
        return magic + combined
    }

    /// Plaintext for a sealed payload. An older unsealed backup is returned as itself.
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

    private static func readKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            throw Failure.keychain(status)
        }
        return data
    }

    private static func writeKey(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw Failure.keychain(status)
        }
    }
}
