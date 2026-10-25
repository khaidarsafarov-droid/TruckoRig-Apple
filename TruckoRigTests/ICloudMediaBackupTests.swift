import XCTest
@testable import TruckoRig

/// Photos and scans beside the Android v2 file. No Apple ID and no network.
@MainActor
final class ICloudMediaBackupTests: XCTestCase {

    private let token = "123456789:AAHabcdefghijklmnopqrstuvwxyz0123456789"
    private var directories: [URL] = []

    override func tearDown() {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
        super.tearDown()
    }

    func testIncrementalUploadRetainsADeletedFileAndDoesNotTouchTheJson() async throws {
        let fixture = try await makeFixture()
        let jsonAfterFirst = try XCTUnwrap(try fixture.store.read(accountId: BackupAccount.localDev))
        let decoded = try BackupDataCodec.decode(String(decoding: jsonAfterFirst, as: UTF8.self))
        XCTAssertEqual(decoded.schemaVersion, BackupSchema.v2)
        XCTAssertFalse(String(decoding: jsonAfterFirst, as: UTF8.self).contains("contentHash"))
        XCTAssertFalse(String(decoding: jsonAfterFirst, as: UTF8.self).contains(token))
        XCTAssertFalse(String(decoding: jsonAfterFirst, as: UTF8.self).contains("GPSLAT"))

        let writesAfterFirst = fixture.store.mediaWrites
        XCTAssertEqual(writesAfterFirst.count, 2)
        XCTAssertFalse(writesAfterFirst.contains { $0.hasSuffix("secret.jpg") })
        XCTAssertEqual(fixture.store.manifestWriteCount, 1)
        let cloudRoot = try XCTUnwrap(fixture.store.mediaRoot(accountId: BackupAccount.localDev))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudRoot.appendingPathComponent("photos/secret.jpg").path))
        XCTAssertFalse(secretExists(in: cloudRoot))

        await fixture.controller.syncNow()
        XCTAssertEqual(fixture.store.mediaWrites, writesAfterFirst)
        XCTAssertEqual(fixture.store.manifestWriteCount, 1)
        let jsonAfterSecond = try XCTUnwrap(try fixture.store.read(accountId: BackupAccount.localDev))
        XCTAssertEqual(jsonAfterSecond, jsonAfterFirst)

        let photo = try XCTUnwrap(try fixture.database.fetchGraph().photos.first { $0.fileName != "secret.jpg" })
        let photoURL = try XCTUnwrap(fixture.local.existingFile(fileName: photo.fileName, filePath: photo.filePath, kind: .photo))
        try Data("GPSLAT:35.123;GPSLON:-78.456-EDIT".utf8).write(to: photoURL)
        await fixture.controller.syncNow()
        XCTAssertEqual(fixture.store.mediaWrites.filter { $0.hasSuffix(photo.fileName) }.count, 2)
        XCTAssertEqual(fixture.store.manifestWriteCount, 2)

        let scan = try XCTUnwrap(try fixture.database.fetchGraph().scans.first)
        let scanCloud = cloudRoot.appendingPathComponent("scans").appendingPathComponent(scan.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: scanCloud.path))
        try fixture.database.delete(scan)
        fixture.local.delete(fileName: scan.fileName, filePath: scan.filePath, kind: .scan)
        await fixture.controller.syncNow()
        XCTAssertTrue(FileManager.default.fileExists(atPath: scanCloud.path))
        XCTAssertEqual(fixture.store.mediaWrites.filter { $0.hasSuffix(scan.fileName) }.count, 1)
        let manifest = try manifestItems(fixture.store)
        XCTAssertTrue(manifest.contains { $0.fileName == scan.fileName })
        XCTAssertFalse(manifest.contains { $0.fileName == "secret.jpg" })
        XCTAssertFalse(manifest.contains { $0.relativePath.contains("receipts") })
        let jsonAfterDelete = try XCTUnwrap(try fixture.store.read(accountId: BackupAccount.localDev))
        XCTAssertEqual(jsonAfterDelete, jsonAfterFirst)

        let documents = try XCTUnwrap(fixture.store.documentsURL())
        let names = try FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        XCTAssertTrue(names.contains(ICloudBackupPolicy.containerFileName(accountId: BackupAccount.localDev)))
        XCTAssertTrue(names.contains(ICloudMediaPolicy.folderName))
    }

    func testRestoreKeepsGeolocationAndSkipsAFileThatIsNotLocalYet() async throws {
        let fixture = try await makeFixture()
        var manifest = try ICloudMediaPolicy.decode(
            String(decoding: try XCTUnwrap(try fixture.store.readManifest(accountId: BackupAccount.localDev)), as: UTF8.self)
        )
        let missing = ICloudMediaPolicy.Item(
            recordId: "22222222-2222-2222-2222-222222222222",
            kind: ICloudMediaPolicy.Kind.photo,
            fileName: "missing.jpg",
            contentHash: "abc",
            byteCount: 4,
            modifiedAt: 1
        )
        manifest.items.append(missing)
        try fixture.store.writeManifest(
            Data(ICloudMediaPolicy.encode(manifest).utf8),
            accountId: BackupAccount.localDev
        )
        fixture.store.notDownloadedRelativePaths = ["photos/missing.jpg"]
        let jsonBefore = try XCTUnwrap(try fixture.store.read(accountId: BackupAccount.localDev))

        let restoredDatabase = try AppDatabase.ephemeral()
        let defaults = UserDefaults(suiteName: "media-restore-\(UUID().uuidString)")!
        let settings = AppSettings(scope: .local, defaults: defaults)
        let local = remember(MediaStore(scope: .local, root: try makeRoot()))
        let preview = try BackupService.preview(data: jsonBefore)
        _ = try BackupService.restoreBackupJSON(
            preview.json,
            into: restoredDatabase,
            settings: settings,
            identity: BackupIdentityStore(defaults: defaults),
            media: local,
            allowUnboundAccount: true
        )
        let controller = ICloudBackupController(
            store: fixture.store,
            prefs: ICloudBackupPrefs(defaults: UserDefaults(suiteName: "media-restore-prefs-\(UUID().uuidString)")!)
        )
        controller.mediaStoreOverride = local
        controller.bind(database: restoredDatabase, settings: settings, scope: .local)
        let result = await controller.restoreMedia()

        XCTAssertTrue(result.payload.unavailable.contains("photos/missing.jpg"))
        XCTAssertTrue(fixture.store.downloadRequests.contains("photos/missing.jpg"))
        XCTAssertGreaterThanOrEqual(result.applied.restored, 1)
        let photos = try restoredDatabase.fetchGraph().photos
        let photo = try XCTUnwrap(photos.first { $0.city == "Garner" })
        XCTAssertEqual(photo.latitude ?? 0, 35.123, accuracy: 0.000_1)
        XCTAssertEqual(photo.longitude ?? 0, -78.456, accuracy: 0.000_1)
        XCTAssertEqual(photo.state, "NC")
        XCTAssertEqual(photo.zipCode, "27529")
        XCTAssertEqual(photo.loadId, try restoredDatabase.fetchGraph().loads.first?.id)
        let file = try XCTUnwrap(local.existingFile(fileName: photo.fileName, filePath: photo.filePath, kind: .photo))
        let bytes = try Data(contentsOf: file)
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("GPSLAT:35.123"))
        let scans = try restoredDatabase.fetchGraph().scans
        XCTAssertFalse(scans.isEmpty)
        let jsonAfter = try XCTUnwrap(try fixture.store.read(accountId: BackupAccount.localDev))
        XCTAssertEqual(jsonAfter, jsonBefore)
    }

    func testSecretsAreNotUploadedAndWifiOrPowerDefersMedia() async throws {
        let root = try makeRoot()
        let store = ICloudDriveStore(probe: .available(root))
        let prefs = ICloudBackupPrefs(defaults: UserDefaults(suiteName: "media-secret-\(UUID().uuidString)")!)
        XCTAssertTrue(prefs.mediaEnabled)
        XCTAssertTrue(prefs.wifiOnly)
        let engine = ICloudSyncEngine(store: store, prefs: prefs)
        let poisoned = #"{"schemaVersion":2,"exportedAt":9,"accountId":"local_dev","loads":[],"note":"\#(token)"}"#
        let refused = engine.perform(ICloudSyncRequest(
            accountId: BackupAccount.localDev,
            localNewestMillis: 9,
            hasExportableContent: true,
            payload: Data(poisoned.utf8),
            debounceElapsed: true,
            autoSyncEnabled: true,
            respectsAutoSwitch: true,
            now: 9
        ))
        XCTAssertEqual(refused, .refusedSecret)
        XCTAssertNil(try store.read(accountId: BackupAccount.localDev))

        let database = try AppDatabase.ephemeral()
        let defaults = UserDefaults(suiteName: "media-ocr-\(UUID().uuidString)")!
        let settings = AppSettings(scope: .local, defaults: defaults)
        try database.save(Load(tripId: "T-OCR", date: Date(timeIntervalSince1970: 1_700_000_000), totalRate: 1, totalMiles: 1))
        let local = remember(MediaStore(scope: .local, root: try makeRoot()))
        let fields = StoredScanFields(
            fileName: "ocr.pdf",
            filePath: "scans/ocr.pdf",
            timestampMillis: 1_700_000_000_000,
            fileSizeBytes: 8,
            pageCount: 1,
            ocrText: "see \(token) please",
            loadId: nil,
            category: ScanDocumentCategory.other.rawValue
        )
        _ = try MediaRepository(database: database, store: local, onDidSave: nil)
            .saveScan(fields: fields, pdf: Data("%PDF-1.4 clean".utf8), load: nil)
        let controller = ICloudBackupController(store: store, prefs: prefs)
        controller.mediaStoreOverride = local
        controller.lowPowerModeOverride = false
        controller.onWifi = false
        controller.bind(database: database, settings: settings, scope: .local)
        await controller.syncNow()
        XCTAssertEqual(controller.mediaNotice, .waitingForWifi)
        XCTAssertTrue(store.mediaWrites.isEmpty)

        controller.onWifi = true
        controller.lowPowerModeOverride = true
        await controller.syncNow()
        XCTAssertEqual(controller.mediaNotice, .waitingForPower)
        XCTAssertTrue(store.mediaWrites.isEmpty)

        controller.lowPowerModeOverride = false
        await controller.syncNow()
        XCTAssertEqual(store.mediaWrites, ["scans/ocr.pdf"])
        let manifest = try manifestItems(store)
        let text = ICloudMediaPolicy.encode(ICloudMediaPolicy.Manifest(accountId: "local_dev", updatedAt: 1, items: manifest))
        XCTAssertFalse(text.contains(token))
        XCTAssertTrue(text.contains("***"))
        XCTAssertFalse(text.contains("botToken"))
        XCTAssertFalse(text.contains("passphrase"))
        let json = try XCTUnwrap(try store.read(accountId: BackupAccount.localDev))
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains(token))
    }

    private struct Fixture {
        var database: AppDatabase
        var local: MediaStore
        var store: ICloudDriveStore
        var controller: ICloudBackupController
    }

    private func makeFixture() async throws -> Fixture {
        let database = try AppDatabase.ephemeral()
        let defaults = UserDefaults(suiteName: "media-db-\(UUID().uuidString)")!
        let settings = AppSettings(scope: .local, defaults: defaults)
        let local = remember(MediaStore(scope: .local, root: try makeRoot()))
        let when = Date(timeIntervalSince1970: 1_721_570_000)
        let loadId = UUID()
        let load = Load(id: loadId, tripId: "T-MEDIA", date: when, totalRate: 12, totalMiles: 3)
        try database.save(load)
        let repository = MediaRepository(database: database, store: local, onDidSave: nil)
        let photoFields = StoredPhotoFields.make(
            tripId: "T-MEDIA",
            loadDate: "2026-07-21",
            location: LocationStamp(latitude: 35.123, longitude: -78.456, city: "Garner", state: "NC", zipCode: "27529"),
            timestamp: when,
            loadId: loadId.uuidString
        )
        _ = try repository.savePhoto(
            fields: photoFields,
            jpeg: Data("GPSLAT:35.123;GPSLON:-78.456".utf8),
            load: load
        )
        let scanFields = StoredScanFields.make(
            tripId: "T-MEDIA",
            loadDate: "2026-07-21",
            timestamp: when,
            fileSizeBytes: 12,
            pageCount: 2,
            ocrText: "BOL",
            loadId: loadId.uuidString,
            category: .load
        )
        _ = try repository.saveScan(fields: scanFields, pdf: Data("%PDF-1.4 scan".utf8), load: load)
        let secret = StoredPhotoFields(
            fileName: "secret.jpg",
            filePath: "photos/secret.jpg",
            latitude: 1,
            longitude: 2,
            city: "",
            state: "",
            zipCode: "",
            timestampMillis: 20,
            loadId: nil
        )
        _ = try repository.savePhoto(fields: secret, jpeg: Data(token.utf8), load: nil)
        _ = try local.writeReceipt(data: Data("receipt-bytes".utf8), fileName: "receipt_keep.jpg")

        let store = ICloudDriveStore(probe: .available(try makeRoot()))
        let controller = ICloudBackupController(
            store: store,
            prefs: ICloudBackupPrefs(defaults: UserDefaults(suiteName: "media-prefs-\(UUID().uuidString)")!)
        )
        controller.mediaStoreOverride = local
        controller.lowPowerModeOverride = false
        controller.onWifi = true
        controller.bind(database: database, settings: settings, scope: .local)
        await controller.syncNow()
        return Fixture(database: database, local: local, store: store, controller: controller)
    }

    private func manifestItems(_ store: ICloudDriveStore) throws -> [ICloudMediaPolicy.Item] {
        let data = try XCTUnwrap(try store.readManifest(accountId: BackupAccount.localDev))
        return try ICloudMediaPolicy.decode(String(decoding: data, as: UTF8.self)).items
    }

    private func secretExists(in root: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return false }
        for case let url as URL in enumerator {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            if ICloudMediaPolicy.fileIsSecret(Array(data)) { return true }
        }
        return false
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("icloud-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        directories.append(root)
        return root
    }

    private func remember(_ store: MediaStore) -> MediaStore {
        directories.append(store.root)
        return store
    }
}
