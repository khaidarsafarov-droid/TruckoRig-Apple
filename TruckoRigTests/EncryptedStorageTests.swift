import XCTest
@testable import TruckoRig

/// Encryption, the Keychain passphrase, the one-time SwiftData copy, and backup `parsedAt`.
final class EncryptedStorageTests: XCTestCase {

    private var directories: [URL] = []
    private var keychainAccounts: [String] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
        for account in keychainAccounts {
            try? DatabasePassphraseStore(account: account).delete()
        }
        keychainAccounts = []
        super.tearDown()
    }

    func testEncryptedFileRoundTripsAndHidesTheTrip() throws {
        let url = try temporaryFile("journal.sqlite")
        let passphrase = Data((0..<32).map(UInt8.init))
        let tripId = "CIPHERTRIP9F3AKHAIDAR"
        let written = Date(timeIntervalSince1970: 1_700_000_000)
        try writeLoad(at: url, passphrase: passphrase, tripId: tripId, date: written)

        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(bytes.starts(with: Data("SQLite format 3".utf8)))
        XCTAssertNil(bytes.range(of: Data(tripId.utf8)))
        let wal = URL(fileURLWithPath: url.path + "-wal")
        if FileManager.default.fileExists(atPath: wal.path) {
            let walBytes = try Data(contentsOf: wal)
            XCTAssertNil(walBytes.range(of: Data(tripId.utf8)))
        }

        XCTAssertThrowsError(try AppDatabase.open(at: url, passphrase: Data(repeating: 0x11, count: 32)))

        let reopened = try AppDatabase.open(at: url, passphrase: passphrase)
        let loaded = try reopened.load(tripId: tripId)
        XCTAssertEqual(loaded?.tripId, tripId)
        XCTAssertEqual(loaded?.totalRate ?? -1, 2500, accuracy: 0.001)
        XCTAssertEqual(loaded?.weekNumber, 43)
        XCTAssertEqual(loaded?.year, 2025)
        XCTAssertEqual(loaded?.date.timeIntervalSince1970 ?? -1, written.timeIntervalSince1970, accuracy: 0.001)
    }

    func testPassphraseIs32BytesStableAndStaysOnThisDevice() throws {
        let account = "test-\(UUID().uuidString)"
        keychainAccounts.append(account)
        let store = DatabasePassphraseStore(account: account)

        let created = try store.getOrCreate()
        XCTAssertEqual(created.count, DatabasePassphraseStore.byteCount)
        let again = try store.getOrCreate()
        XCTAssertEqual(created, again)

        let generated = try DatabasePassphraseStore.randomBytes()
        XCTAssertEqual(generated.count, 32)
        XCTAssertNotEqual(generated, created)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: DatabasePassphraseStore.service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        XCTAssertEqual(status, errSecSuccess)
        let attributes = item as? [String: Any]
        let accessible = attributes?[kSecAttrAccessible as String] as? String
        XCTAssertEqual(accessible, DatabasePassphraseStore.accessibility as String)
    }

    func testLegacySwiftDataImportKeepsTripDateAndDoesNotRepeat() throws {
        let directory = try temporaryDirectory()
        let legacy = directory.appendingPathComponent("TruckoRig_local.store")
        let encrypted = directory.appendingPathComponent("TruckoRig_local.sqlite")
        let tripId = "T-116KYL6KW"
        let referenceSeconds = 654_321.0
        let loadId = UUID()
        let stopId = UUID()
        try writeLegacyStore(
            at: legacy,
            loadId: loadId,
            stopId: stopId,
            tripId: tripId,
            referenceSeconds: referenceSeconds
        )

        let database = try AppDatabase.open(at: encrypted, passphrase: Data(repeating: 0xAB, count: 32))
        let outcome = try SwiftDataMigration.run(legacyStoreURL: legacy, database: database)
        XCTAssertEqual(outcome, .imported(1))

        let loaded = try database.load(tripId: tripId)
        XCTAssertEqual(loaded?.id, loadId)
        XCTAssertEqual(loaded?.tripId, tripId)
        XCTAssertEqual(loaded?.weekNumber, 43)
        XCTAssertEqual(loaded?.year, 2025)
        let expected = Date(timeIntervalSinceReferenceDate: referenceSeconds)
        XCTAssertEqual(
            loaded?.date.timeIntervalSinceReferenceDate ?? -1,
            expected.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )
        XCTAssertEqual(loaded?.stops?.count, 1)
        XCTAssertEqual(loaded?.stops?.first?.city, "Garner")
        XCTAssertEqual(loaded?.stops?.first?.state, "NC")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path + ".premigration"))

        let second = try SwiftDataMigration.run(legacyStoreURL: legacy, database: database)
        XCTAssertEqual(second, .alreadyImported)
        XCTAssertEqual(try database.loads().count, 1)
    }

    func testMissingLegacyStoreIsANoOp() throws {
        let directory = try temporaryDirectory()
        let missing = directory.appendingPathComponent("TruckoRig_local.store")
        let database = try AppDatabase.ephemeral()

        let outcome = try SwiftDataMigration.run(legacyStoreURL: missing, database: database)
        XCTAssertEqual(outcome, .nothingToImport)
        XCTAssertTrue(try database.legacyImportIsDone())
        XCTAssertTrue(try database.loads().isEmpty)

        let second = try SwiftDataMigration.run(legacyStoreURL: missing, database: database)
        XCTAssertEqual(second, .alreadyImported)
    }

    func testEmptyLegacyStoreIsQuarantinedWithoutImporting() throws {
        let directory = try temporaryDirectory()
        let legacy = directory.appendingPathComponent("TruckoRig_local.store")
        try writeEmptyLegacyStore(at: legacy)
        let database = try AppDatabase.ephemeral()

        let outcome = try SwiftDataMigration.run(legacyStoreURL: legacy, database: database)
        XCTAssertEqual(outcome, .nothingToImport)
        XCTAssertTrue(try database.legacyImportIsDone())
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path + ".premigration"))
    }

    func testBackupRestoreKeepsTripIdAndParsedAt() async throws {
        try await MainActor.run { try backupRestoreKeepsTripIdAndParsedAt() }
    }

    @MainActor
    private func backupRestoreKeepsTripIdAndParsedAt() throws {
        let database = try AppDatabase.ephemeral()
        let parsedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let tripId = "T-BACKUP-1"
        let load = Load(
            tripId: tripId,
            date: parsedAt,
            totalRate: 2500,
            totalMiles: 850,
            parsedAt: parsedAt,
            updatedAt: updatedAt
        )
        try database.save(load)

        var snapshot = try SnapshotBuilder.build(from: database)
        snapshot.loads[0].parsedAt = Date(timeIntervalSince1970: 1_800_000_000)
        snapshot.loads[0].updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        snapshot.loads[0].totalRate = 2600
        snapshot.loads[0].tripId = tripId

        let report = try SnapshotApplier.apply(snapshot, to: database)
        XCTAssertEqual(report.updated, 1)

        let stored = try database.load(tripId: tripId)
        XCTAssertEqual(stored?.tripId, tripId)
        XCTAssertEqual(stored?.parsedAt.timeIntervalSince1970 ?? -1, parsedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(stored?.totalRate ?? -1, 2600, accuracy: 0.001)
        XCTAssertEqual(try database.loads().count, 1)
    }

    // MARK: - Fixtures

    private func writeLoad(at url: URL, passphrase: Data, tripId: String, date: Date) throws {
        let database = try AppDatabase.open(at: url, passphrase: passphrase)
        let load = Load(
            tripId: tripId,
            date: date,
            totalRate: 2500,
            totalMiles: 850,
            weekNumber: 43,
            year: 2025,
            parsedAt: date,
            updatedAt: date
        )
        try database.save(load)
        try database.checkpoint()
    }

    private func writeEmptyLegacyStore(at url: URL) throws {
        let connection = try SystemSQLite.open(path: url.path, readOnly: false)
        try connection.execute("CREATE TABLE ZLOAD (Z_PK INTEGER PRIMARY KEY, ZTRIPID TEXT, ZID BLOB)")
    }

    private func writeLegacyStore(
        at url: URL,
        loadId: UUID,
        stopId: UUID,
        tripId: String,
        referenceSeconds: Double
    ) throws {
        let connection = try SystemSQLite.open(path: url.path, readOnly: false)
        try connection.execute("""
        CREATE TABLE ZLOAD (
            Z_PK INTEGER PRIMARY KEY,
            ZID BLOB,
            ZTRIPID TEXT,
            ZDATE REAL,
            ZTOTALRATE REAL,
            ZTOTALMILES REAL,
            ZWEEKNUMBER INTEGER,
            ZYEAR INTEGER,
            ZPARSEDAT REAL,
            ZUPDATEDAT REAL,
            ZPUCOUNT INTEGER,
            ZDELCOUNT INTEGER,
            ZSTOPCOUNT INTEGER,
            ZISDISPUTE INTEGER,
            ZDISPUTECOMPLETED INTEGER,
            ZDURATIONDAYS REAL
        )
        """)
        try connection.execute("""
        INSERT INTO ZLOAD (
            Z_PK, ZID, ZTRIPID, ZDATE, ZTOTALRATE, ZTOTALMILES, ZWEEKNUMBER, ZYEAR,
            ZPARSEDAT, ZUPDATEDAT, ZPUCOUNT, ZDELCOUNT, ZSTOPCOUNT, ZISDISPUTE, ZDISPUTECOMPLETED, ZDURATIONDAYS
        ) VALUES (
            1, X'\(hex(loadId))', '\(tripId)', \(referenceSeconds), 2500, 850, 43, 2025,
            \(referenceSeconds), \(referenceSeconds), 1, 1, 2, 0, 0, 1
        )
        """)
        try connection.execute("""
        INSERT INTO ZLOAD (Z_PK, ZTRIPID) VALUES (2, '')
        """)
        try connection.execute("""
        CREATE TABLE ZSTOP (
            Z_PK INTEGER PRIMARY KEY,
            ZLOAD INTEGER,
            ZID BLOB,
            ZTYPE TEXT,
            ZSTOPNUMBER INTEGER,
            ZFULLADDRESS TEXT,
            ZCITY TEXT,
            ZSTATE TEXT
        )
        """)
        try connection.execute("""
        INSERT INTO ZSTOP (Z_PK, ZLOAD, ZID, ZTYPE, ZSTOPNUMBER, ZFULLADDRESS, ZCITY, ZSTATE)
        VALUES (1, 1, X'\(hex(stopId))', 'PU', 1, '1 Main St', 'Garner', 'NC')
        """)
    }

    private func hex(_ uuid: UUID) -> String {
        withUnsafeBytes(of: uuid.uuid) { buffer in
            buffer.map { String(format: "%02X", $0) }.joined()
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("truckorig-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }

    private func temporaryFile(_ name: String) throws -> URL {
        try temporaryDirectory().appendingPathComponent(name)
    }
}
