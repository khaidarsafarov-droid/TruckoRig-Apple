import XCTest
@testable import TruckoRig

/// iCloud Drive file, conflict choice, and a missing account. No network and no Apple ID.
final class ICloudBackupTests: XCTestCase {

    func testContainerFileRoundTripsThroughTheCoordinatorAndKeepsOneFile() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ICloudDriveStore(probe: .available(root))
        let backup = BackupData(
            schemaVersion: 2,
            version: 2,
            exportedAt: 1_700_000_000_000,
            accountId: BackupAccount.localDev,
            loads: [BackupLoad(id: "L-1", tripId: "T-FILE", date: "2026-07-21", totalRateCents: 100)],
            originDevice: "iPhone",
            originPlatform: ICloudBackupPolicy.originPlatformIOS
        )
        let json = BackupDataCodec.encode(backup)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("telegram"))
        XCTAssertFalse(json.contains("botToken"))
        XCTAssertFalse(json.contains("passphrase"))
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(Data(json.utf8))
        try store.write(bom, accountId: BackupAccount.localDev)
        try store.write(bom, accountId: BackupAccount.localDev)

        let read = try XCTUnwrap(try store.read(accountId: BackupAccount.localDev))
        let preview = try BackupService.preview(data: read)
        XCTAssertEqual(preview.exportedAt, backup.exportedAt)
        XCTAssertEqual(preview.originDevice, "iPhone")
        XCTAssertEqual(preview.originPlatform, "ios")
        XCTAssertFalse(preview.accountMismatch)
        XCTAssertFalse(preview.unbound)
        let decoded = try BackupDataCodec.decode(preview.json)
        XCTAssertEqual(decoded.loads.map(\.tripId), ["T-FILE"])

        let documents = try XCTUnwrap(store.documentsURL())
        let files = try FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "json" }.count, 1)
        XCTAssertEqual(
            files.map(\.lastPathComponent),
            [ICloudBackupPolicy.containerFileName(accountId: BackupAccount.localDev)]
        )
    }

    func testSyncKeepsTheNewerRemoteAndUploadsTheNewerLocal() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ICloudDriveStore(probe: .available(root))
        let prefs = ICloudBackupPrefs(defaults: UserDefaults(suiteName: "icloud-\(UUID().uuidString)")!)
        let engine = ICloudSyncEngine(store: store, prefs: prefs)

        let remote = payload(exportedAt: 5_000, accountId: "local_dev", trip: "REMOTE")
        try store.write(Data(remote.utf8), accountId: BackupAccount.localDev)
        let kept = engine.perform(request(
            localNewest: 1_000,
            payload: Data(payload(exportedAt: 1_000, accountId: "local_dev", trip: "LOCAL").utf8)
        ))
        XCTAssertEqual(kept, .keepRemote(5_000))
        let stillRemote = try XCTUnwrap(try store.read(accountId: BackupAccount.localDev))
        XCTAssertTrue(String(decoding: stillRemote, as: UTF8.self).contains("REMOTE"))

        let uploaded = engine.perform(request(
            localNewest: 9_000,
            payload: Data(payload(exportedAt: 9_000, accountId: "local_dev", trip: "LOCAL").utf8)
        ))
        XCTAssertEqual(uploaded, .uploaded(9_000))
        XCTAssertEqual(prefs.lastUploadedExportedAt, 9_000)
        let nowLocal = try XCTUnwrap(try store.read(accountId: BackupAccount.localDev))
        XCTAssertTrue(String(decoding: nowLocal, as: UTF8.self).contains("LOCAL"))
        XCTAssertFalse(String(decoding: nowLocal, as: UTF8.self).localizedCaseInsensitiveContains("telegram"))
    }

    func testMissingICloudDoesNotCrashOrWrite() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for probe in [ICloudDriveStore.Probe.signedOut, .containerMissing] {
            let store = ICloudDriveStore(probe: probe)
            let prefs = ICloudBackupPrefs(defaults: UserDefaults(suiteName: "icloud-\(UUID().uuidString)")!)
            let engine = ICloudSyncEngine(store: store, prefs: prefs)
            let outcome = engine.perform(request(
                localNewest: 9_000,
                payload: Data(payload(exportedAt: 9_000, accountId: "local_dev", trip: "LOCAL").utf8)
            ))
            XCTAssertEqual(outcome, .unavailable)
            XCTAssertThrowsError(try store.read(accountId: BackupAccount.localDev)) { error in
                XCTAssertEqual(error as? ICloudDriveStore.Failure, .unavailable)
            }
        }
        let names = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertTrue(names.isEmpty)

        let source = try AppDatabase.ephemeral()
        let defaults = UserDefaults(suiteName: "icloud-export-\(UUID().uuidString)")!
        let settings = AppSettings(scope: .local, defaults: defaults)
        try source.save(Load(tripId: "T-FILE", date: Date(), totalRate: 10, totalMiles: 1))
        let file = try BackupService.exportFile(
            from: source,
            settings: settings,
            identity: BackupIdentityStore(defaults: defaults)
        )
        XCTAssertFalse(file.data.isEmpty)
        XCTAssertFalse(String(decoding: file.data, as: UTF8.self).contains("originDevice"))
    }

    @MainActor
    func testAccountMismatchIsConfirmedAndNewerSchemaIsRejected() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ICloudDriveStore(probe: .available(root))
        let prefs = ICloudBackupPrefs(defaults: UserDefaults(suiteName: "icloud-\(UUID().uuidString)")!)
        let controller = ICloudBackupController(store: store, prefs: prefs)
        let database = try AppDatabase.ephemeral()
        let defaults = UserDefaults(suiteName: "icloud-restore-\(UUID().uuidString)")!
        let settings = AppSettings(scope: .local, defaults: defaults)
        let local = Load(
            tripId: "T-LOCAL",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            totalRate: 10,
            totalMiles: 1,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        try database.save(local)
        controller.bind(database: database, settings: settings, scope: .local)

        let foreign = payload(exportedAt: 1_000, accountId: "google_user", trip: "ANDROID", platform: "android", device: "Pixel")
        try store.write(Data(foreign.utf8), accountId: BackupAccount.localDev)
        await controller.reloadRemote()
        let remote = try XCTUnwrap(controller.remote)
        XCTAssertTrue(remote.accountMismatch)
        XCTAssertEqual(remote.originPlatform, "android")
        XCTAssertEqual(remote.originDevice, "Pixel")
        XCTAssertTrue(controller.copyIsOlderThanLocal())
        XCTAssertThrowsError(try controller.restore(confirmed: false)) { error in
            XCTAssertEqual(error as? ICloudBackupController.Refusal, .blocked(.foreignAccount))
        }
        XCTAssertEqual(try database.fetchGraph().loads.map(\.tripId), ["T-LOCAL"])

        _ = try controller.restore(confirmed: true)
        XCTAssertEqual(try database.fetchGraph().loads.map(\.tripId), ["ANDROID"])

        let preview = try BackupService.preview(data: Data(foreign.utf8))
        XCTAssertTrue(preview.accountMismatch)
        XCTAssertThrowsError(
            try BackupService.restoreBackupJSON(
                preview.json,
                into: try AppDatabase.ephemeral(),
                settings: settings,
                identity: BackupIdentityStore(defaults: defaults),
                media: MediaStore(scope: .local, root: root),
                allowUnboundAccount: false,
                allowForeignAccount: false
            )
        ) { error in
            XCTAssertEqual(error as? BackupService.Failure, .wrongAccount)
        }

        let newer = Data(#"{"schemaVersion":99,"loads":[]}"#.utf8)
        try store.write(newer, accountId: BackupAccount.localDev)
        await controller.reloadRemote()
        XCTAssertEqual(controller.notice, .schemaTooNew)
        XCTAssertNil(controller.remote)
        XCTAssertThrowsError(try BackupService.preview(data: newer)) { error in
            XCTAssertEqual(error as? BackupService.Failure, .schemaTooNew(99))
        }
        let left = try XCTUnwrap(try store.read(accountId: BackupAccount.localDev))
        XCTAssertTrue(String(decoding: left, as: UTF8.self).contains("99"))
    }

    func testMetadataQueryLooksUpTheAccountFileInICloudDocuments() {
        let name = ICloudBackupPolicy.containerFileName(accountId: BackupAccount.localDev)
        let predicate = ICloudMetadataQueryPlan.predicate(fileName: name)
        XCTAssertTrue(predicate.predicateFormat.contains(name))
        XCTAssertEqual(
            ICloudMetadataQueryPlan.ubiquitousDocumentsScope,
            NSMetadataQueryUbiquitousDocumentsScope
        )
        let bundles = [Bundle.main] + Bundle.allBundles
        let host = bundles.first { bundle in
            let identifiers = bundle.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
            return identifiers?.contains(ICloudBackupPolicy.backgroundTaskIdentifier) == true
        }
        let identifiers = host?.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        XCTAssertTrue(identifiers?.contains(ICloudBackupPolicy.backgroundTaskIdentifier) == true)
        let containers = host?.object(forInfoDictionaryKey: "NSUbiquitousContainers") as? [String: Any]
        XCTAssertNotNil(containers?[ICloudBackupPolicy.containerIdentifier])
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("icloud-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func request(localNewest: Int64, payload: Data) -> ICloudSyncRequest {
        ICloudSyncRequest(
            accountId: BackupAccount.localDev,
            localNewestMillis: localNewest,
            hasExportableContent: true,
            payload: payload,
            debounceElapsed: true,
            autoSyncEnabled: true,
            respectsAutoSwitch: true,
            now: localNewest
        )
    }

    private func payload(
        exportedAt: Int64,
        accountId: String,
        trip: String,
        platform: String? = nil,
        device: String? = nil
    ) -> String {
        var fields = """
        {"schemaVersion":2,"version":2,"exportedAt":\(exportedAt),"accountId":"\(accountId)"
        """
        if let platform { fields += ",\"originPlatform\":\"\(platform)\"" }
        if let device { fields += ",\"originDevice\":\"\(device)\"" }
        fields += ",\"loads\":[{\"id\":\"L-1\",\"tripId\":\"\(trip)\",\"date\":\"2026-07-21\",\"totalRate\":100}]}"
        return fields
    }
}
