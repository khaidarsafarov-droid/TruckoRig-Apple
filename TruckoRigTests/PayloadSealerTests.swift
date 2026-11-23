import XCTest
@testable import TruckoRig

final class PayloadSealerTests: XCTestCase {
    #if DEBUG
    override func tearDown() {
        CloudPayloadSealer.testingKey = nil
        CloudPayloadSealer.engine.keyStore = SystemSealerKeyStore()
        super.tearDown()
    }
    #endif

    func testOpenDoesNotCreateAKey() throws {
        #if DEBUG
        let memory = MemorySealerKeyStore()
        CloudPayloadSealer.testingKey = nil
        CloudPayloadSealer.engine.keyStore = memory
        let sealed = CloudPayloadSealer.magic + Data(repeating: 0xAB, count: 48)
        XCTAssertThrowsError(try CloudPayloadSealer.open(sealed)) { error in
            XCTAssertEqual(error as? PayloadSealer.Failure, .keyUnavailable)
        }
        XCTAssertEqual(memory.addCount, 0)
        #else
        throw XCTSkip("The in-memory key store is compiled into Debug builds.")
        #endif
    }

    func testDuplicateAddRereadsTheStoredKey() throws {
        #if DEBUG
        let memory = MemorySealerKeyStore()
        let winner = Data(repeating: 0x11, count: 32)
        memory.forceDuplicate = true
        memory.winner = winner
        CloudPayloadSealer.testingKey = nil
        CloudPayloadSealer.engine.keyStore = memory
        let plain = Data("hello".utf8)
        let sealed = try CloudPayloadSealer.seal(plain)
        XCTAssertEqual(memory.addCount, 1)
        XCTAssertEqual(memory.item, winner)
        CloudPayloadSealer.testingKey = winner
        XCTAssertEqual(try CloudPayloadSealer.open(sealed), plain)
        #else
        throw XCTSkip("The in-memory key store is compiled into Debug builds.")
        #endif
    }

    func testWrongKeySealedFileIsNotScoredZero() throws {
        #if DEBUG
        CloudPayloadSealer.testingKey = Data(repeating: 0x03, count: 32)
        let json = #"{"schemaVersion":2,"version":2,"exportedAt":50,"accountId":"local_dev","loads":[],"paychecks":[],"diesel":[],"maintenanceTasks":[],"maintenanceArchive":[]}"#
        let sealed = try CloudPayloadSealer.seal(Data(json.utf8))
        CloudPayloadSealer.testingKey = Data(repeating: 0x04, count: 32)
        XCTAssertNil(ICloudDriveStore.exportedAt(in: sealed))
        #else
        throw XCTSkip("Sealer test keys are compiled into Debug builds.")
        #endif
    }
}
