import XCTest
@testable import TruckoRig

/// The BotFather token is a Keychain item. CI signs the simulator host so this cannot skip.
final class TelegramTokenStoreTests: XCTestCase {

    func testTokenRoundTripsInTheKeychainAndIsNotLeftBehind() throws {
        let account = "telegram-\(UUID().uuidString)"
        let store = TelegramTokenStore(account: account)
        defer { try? store.delete() }
        let token = "123456789:AAHabcdefghijklmnopqrstuvwxyz0123456789"
        do {
            try store.write("  \(token)  ")
        } catch TelegramTokenStoreError.keychain(let status) {
            XCTFail("Keychain refused the simulator host (\(status)).")
            return
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
