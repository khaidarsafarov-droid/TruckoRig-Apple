import CryptoKit
import Foundation
import Security

/// AES-GCM envelope shared by the iCloud backup and the share inbox.
///
/// `open` only reads the key. A missing item throws `keyUnavailable` and does not call
/// `SecItemAdd`. `seal` creates the key, under a lock, and on `errSecDuplicateItem` it reads the
/// item another writer stored and uses those bytes. Before the sealed bytes are returned, they
/// are opened again with the key read back from the store, so a cloud file is not replaced with
/// ciphertext this phone cannot read.
final class PayloadSealer: @unchecked Sendable {
    struct Configuration: Sendable {
        var magic: Data
        var service: String
        var account: String
        var accessGroup: String?
        var synchronizable: Bool
        var accessibility: CFString
    }

    enum Failure: Error, Equatable {
        case keyUnavailable
        case authenticationFailed
        case keychain(OSStatus)
        case seal
    }

    let configuration: Configuration
    private let lock = NSLock()
    #if DEBUG
    var testingKey: Data?
    var keyStore: SealerKeyStore = SystemSealerKeyStore()
    #else
    private let keyStore: SealerKeyStore = SystemSealerKeyStore()
    #endif

    init(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func open(_ data: Data) throws -> Data {
        guard data.starts(with: configuration.magic) else { return data }
        let keyData = try readKey()
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(configuration.magic.count))
            return try AES.GCM.open(box, using: SymmetricKey(data: keyData))
        } catch {
            throw Failure.authenticationFailed
        }
    }

    func seal(_ plain: Data) throws -> Data {
        if plain.starts(with: configuration.magic) { return plain }
        lock.lock()
        defer { lock.unlock() }
        _ = try materializeKeyLocked()
        let keyData = try readKeyLocked()
        let key = SymmetricKey(data: keyData)
        let box = try AES.GCM.seal(plain, using: key)
        guard let combined = box.combined else { throw Failure.seal }
        let sealed = configuration.magic + combined
        let opened = try AES.GCM.open(try AES.GCM.SealedBox(combined: combined), using: key)
        guard opened == plain else { throw Failure.seal }
        return sealed
    }

    private func materializeKeyLocked() throws -> Data {
        if let existing = try readStoredLocked() { return existing }
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return errSecAllocate }
            return SecRandomCopyBytes(kSecRandomDefault, 32, address)
        }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        let added = try keyStore.add(
            service: configuration.service,
            account: configuration.account,
            accessGroup: configuration.accessGroup,
            synchronizable: configuration.synchronizable,
            accessibility: configuration.accessibility,
            data: bytes
        )
        if added == errSecDuplicateItem {
            guard let stored = try readStoredLocked() else { throw Failure.keyUnavailable }
            return stored
        }
        guard added == errSecSuccess else { throw Failure.keychain(added) }
        return bytes
    }

    private func readKey() throws -> Data {
        #if DEBUG
        if let testingKey, testingKey.count == 32 { return testingKey }
        #endif
        lock.lock()
        defer { lock.unlock() }
        return try readKeyLocked()
    }

    private func readKeyLocked() throws -> Data {
        #if DEBUG
        if let testingKey, testingKey.count == 32 { return testingKey }
        #endif
        guard let stored = try readStoredLocked() else { throw Failure.keyUnavailable }
        return stored
    }

    private func readStoredLocked() throws -> Data? {
        #if DEBUG
        if let testingKey, testingKey.count == 32 { return testingKey }
        #endif
        return try keyStore.read(
            service: configuration.service,
            account: configuration.account,
            accessGroup: configuration.accessGroup,
            synchronizable: configuration.synchronizable
        )
    }
}

protocol SealerKeyStore: AnyObject {
    func read(service: String, account: String, accessGroup: String?, synchronizable: Bool) throws -> Data?
    func add(
        service: String,
        account: String,
        accessGroup: String?,
        synchronizable: Bool,
        accessibility: CFString,
        data: Data
    ) throws -> OSStatus
}

final class SystemSealerKeyStore: SealerKeyStore {
    func read(service: String, account: String, accessGroup: String?, synchronizable: Bool) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            throw PayloadSealer.Failure.keychain(status)
        }
        return data
    }

    func add(
        service: String,
        account: String,
        accessGroup: String?,
        synchronizable: Bool,
        accessibility: CFString,
        data: Data
    ) throws -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: accessibility,
            kSecValueData as String: data,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        if synchronizable {
            query[kSecAttrSynchronizable as String] = true
        }
        return SecItemAdd(query as CFDictionary, nil)
    }
}

#if DEBUG
final class MemorySealerKeyStore: SealerKeyStore {
    var item: Data?
    /// Bytes another writer stored, returned after a duplicate add.
    var winner: Data?
    var addCount = 0
    var forceDuplicate = false

    func read(service: String, account: String, accessGroup: String?, synchronizable: Bool) throws -> Data? {
        item
    }

    func add(
        service: String,
        account: String,
        accessGroup: String?,
        synchronizable: Bool,
        accessibility: CFString,
        data: Data
    ) throws -> OSStatus {
        addCount += 1
        if forceDuplicate {
            item = winner
            return errSecDuplicateItem
        }
        if item != nil {
            return errSecDuplicateItem
        }
        item = data
        return errSecSuccess
    }
}
#endif

/// iCloud journal, manifest, and media bytes. The key syncs through iCloud Keychain so another
/// phone signed into the same account can open a sealed backup. `ThisDeviceOnly` cannot sync.
enum CloudPayloadSealer {
    static let magic = Data("TRBK1".utf8)
    static let engine = PayloadSealer(PayloadSealer.Configuration(
        magic: Data("TRBK1".utf8),
        service: "com.truckorig.icloud-payload-key",
        account: "backup",
        accessGroup: nil,
        synchronizable: true,
        accessibility: kSecAttrAccessibleAfterFirstUnlock
    ))

    #if DEBUG
    static var testingKey: Data? {
        get { engine.testingKey }
        set { engine.testingKey = newValue }
    }
    #endif

    static func seal(_ plain: Data) throws -> Data { try engine.seal(plain) }
    static func open(_ data: Data) throws -> Data { try engine.open(data) }
}

/// Share-inbox bytes. The key lives in the App Group keychain access group and does not sync.
enum ShareInboxCrypto {
    static let magic = Data("TRIN1".utf8)
    static let accessGroup = "group.com.truckorig"
    static let engine = PayloadSealer(PayloadSealer.Configuration(
        magic: Data("TRIN1".utf8),
        service: "com.truckorig.share-inbox-key",
        account: "inbox",
        accessGroup: "group.com.truckorig",
        synchronizable: false,
        accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ))

    static func install() {
        ShareInboxCodec.seal = { try seal($0) }
        ShareInboxCodec.open = { try open($0) }
    }

    static func seal(_ plain: Data) throws -> Data {
        do {
            return try engine.seal(plain)
        } catch let error as PayloadSealer.Failure {
            throw ShareInboxOpenError(error)
        }
    }

    static func open(_ data: Data) throws -> Data {
        do {
            return try engine.open(data)
        } catch let error as PayloadSealer.Failure {
            throw ShareInboxOpenError(error)
        }
    }
}

extension ShareInboxOpenError {
    init(_ failure: PayloadSealer.Failure) {
        switch failure {
        case .keyUnavailable:
            self = .keyUnavailable
        case .authenticationFailed:
            self = .authenticationFailed
        case .keychain(let status):
            self = .keychain(status)
        case .seal:
            self = .keychain(errSecInternalError)
        }
    }
}
