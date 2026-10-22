import XCTest
@testable import TruckoRig

/// The BotFather token is a Keychain item. An unsigned simulator has no keychain entitlement.
final class TelegramTokenStoreTests: XCTestCase {

    func testTokenRoundTripsInTheKeychainAndIsNotLeftBehind() throws {
        let account = "telegram-\(UUID().uuidString)"
        let store = TelegramTokenStore(account: account)
        defer { try? store.delete() }
        let token = "123456789:AAHabcdefghijklmnopqrstuvwxyz0123456789"
        do {
            try store.write("  \(token)  ")
        } catch TelegramTokenStoreError.keychain(let status) where status == errSecMissingEntitlement {
            throw XCTSkip("Keychain refused the unsigned simulator (\(status)).")
        }
        XCTAssertEqual(try store.read(), token)
        XCTAssertEqual(
            TelegramTokenStore.accessibility as String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        try store.delete()
        XCTAssertNil(try store.read())
    }
}
