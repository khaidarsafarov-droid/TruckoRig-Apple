import XCTest
@testable import TruckoRigDomain

final class ICloudMediaPolicyTests: XCTestCase {

    private let token = "123456789:AAHabcdefghijklmnopqrstuvwxyz0123456789"

    func testIncrementalPlanKeepsRemoteFilesAndUploadsOnlyChanges() {
        let photo = item(path: "a.jpg", hash: "aaa", modifiedAt: 10, city: "Garner")
        let scan = item(path: "b.pdf", kind: ICloudMediaPolicy.Kind.scan, hash: "bbb", modifiedAt: 11)
        let first = ICloudMediaPolicy.plan(local: [photo, scan], remote: [])
        XCTAssertEqual(first.upload.map(\.fileName), ["a.jpg", "b.pdf"])
        XCTAssertTrue(first.retained.isEmpty)
        XCTAssertTrue(first.deletions.isEmpty)
        XCTAssertTrue(first.rewritesManifest)
        XCTAssertFalse(ICloudMediaPolicy.allowsAutomaticDeletion)
        XCTAssertTrue(ICloudMediaPolicy.deletionRule.contains("never deletes"))

        let same = ICloudMediaPolicy.plan(local: [photo, scan], remote: first.manifestItems)
        XCTAssertTrue(same.upload.isEmpty)
        XCTAssertTrue(same.manifestOnly.isEmpty)
        XCTAssertFalse(same.rewritesManifest)
        XCTAssertTrue(same.deletions.isEmpty)

        var edited = photo
        edited.contentHash = "ccc"
        edited.byteCount = 9
        edited.modifiedAt = 20
        let changed = ICloudMediaPolicy.plan(local: [edited, scan], remote: first.manifestItems)
        XCTAssertEqual(changed.upload.map(\.fileName), ["a.jpg"])
        XCTAssertEqual(changed.unchanged.map(\.fileName), ["b.pdf"])
        XCTAssertTrue(changed.deletions.isEmpty)

        var moved = photo
        moved.city = "Dallas"
        let metadata = ICloudMediaPolicy.plan(local: [moved, scan], remote: first.manifestItems)
        XCTAssertTrue(metadata.upload.isEmpty)
        XCTAssertEqual(metadata.manifestOnly.map(\.city), ["Dallas"])
        XCTAssertTrue(metadata.rewritesManifest)

        let deletedLocally = ICloudMediaPolicy.plan(local: [photo], remote: first.manifestItems)
        XCTAssertTrue(deletedLocally.upload.isEmpty)
        XCTAssertEqual(deletedLocally.retained.map(\.fileName), ["b.pdf"])
        XCTAssertTrue(deletedLocally.deletions.isEmpty)
        XCTAssertFalse(deletedLocally.rewritesManifest)
        XCTAssertEqual(deletedLocally.manifestItems.map(\.fileName), ["a.jpg", "b.pdf"])
    }

    func testSameSizeAndDateSkipsWhenTheHashIsMissing() {
        var local = item(path: "a.jpg", hash: "", modifiedAt: 5)
        local.byteCount = 40
        var remote = local
        let skip = ICloudMediaPolicy.plan(local: [local], remote: [remote])
        XCTAssertTrue(skip.upload.isEmpty)
        XCTAssertFalse(skip.rewritesManifest)

        remote.modifiedAt = 6
        let upload = ICloudMediaPolicy.plan(local: [local], remote: [remote])
        XCTAssertEqual(upload.upload.map(\.fileName), ["a.jpg"])
    }

    func testRestorePartitionKeepsGoingWhenAFileIsMissing() {
        let ready = item(path: "a.jpg", hash: "aaa", modifiedAt: 1)
        let missing = item(path: "b.pdf", kind: ICloudMediaPolicy.Kind.scan, hash: "bbb", modifiedAt: 2)
        let split = ICloudMediaPolicy.restorePartition(
            items: [ready, missing],
            availableRelativePaths: [ready.relativePath]
        )
        XCTAssertEqual(split.ready.map(\.recordId), [ready.recordId])
        XCTAssertEqual(split.unavailable.map(\.recordId), [missing.recordId])
    }

    func testAndroidSchemaV2DoesNotGainMediaOrSecrets() throws {
        let backup = BackupData(
            schemaVersion: 2,
            version: 2,
            exportedAt: 1_700_000_000_000,
            accountId: BackupAccount.localDev,
            loads: [BackupLoad(id: "L-1", tripId: "T-FILE", date: "2026-07-21", totalRateCents: 100)],
            paychecks: [],
            diesel: [],
            maintenanceTasks: [],
            maintenanceArchive: []
        )
        let json = BackupDataCodec.encode(backup)
        let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(
            Set(root?.keys.map { $0 } ?? []),
            ["accountId", "diesel", "exportedAt", "loads", "maintenanceArchive", "maintenanceTasks", "paychecks", "schemaVersion", "version"]
        )
        XCTAssertEqual((root?["schemaVersion"] as? NSNumber)?.intValue, 2)
        XCTAssertFalse(json.contains("photos"))
        XCTAssertFalse(json.contains("scans"))
        XCTAssertFalse(json.contains("contentHash"))
        XCTAssertFalse(json.contains("manifest"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("telegram"))
        XCTAssertFalse(json.contains("botToken"))
        XCTAssertFalse(json.contains("passphrase"))
        XCTAssertFalse(json.contains(token))
        let decoded = try BackupDataCodec.decode(json)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.loads.map(\.tripId), ["T-FILE"])
        XCTAssertEqual(BackupDataCodec.encode(decoded), json)

        let extra = #"{"schemaVersion":2,"version":2,"exportedAt":5,"loads":[],"futureField":true}"#
        XCTAssertEqual(try BackupDataCodec.decode(extra).exportedAt, 5)

        var stamped = item(path: "a.jpg", hash: "abc", modifiedAt: 1)
        stamped.latitude = 35.123
        stamped.longitude = -78.456
        stamped.city = "Garner"
        stamped.ocrText = "note \(token) end"
        let manifest = ICloudMediaPolicy.Manifest(
            accountId: BackupAccount.localDev,
            updatedAt: 9,
            items: [stamped]
        )
        let manifestJSON = ICloudMediaPolicy.encode(manifest)
        XCTAssertFalse(manifestJSON.contains("schemaVersion"))
        XCTAssertFalse(manifestJSON.hasPrefix("TruckoRig_Backup_"))
        XCTAssertFalse(ICloudMediaPolicy.manifestFileName.hasPrefix("TruckoRig_Backup_"))
        XCTAssertThrowsError(try BackupDataCodec.decode(manifestJSON)) { error in
            XCTAssertEqual(error as? BackupDecodeError, .invalidFormat)
        }
        let roundTrip = try ICloudMediaPolicy.decode(manifestJSON)
        XCTAssertEqual(roundTrip.items.first?.latitude, 35.123)
        XCTAssertEqual(roundTrip.items.first?.longitude, -78.456)
        XCTAssertEqual(roundTrip.items.first?.city, "Garner")
        XCTAssertFalse(manifestJSON.contains(token))
        XCTAssertTrue(manifestJSON.contains("***"))
    }

    func testSecretsStayOutOfTheManifestAndTheFileCheck() {
        XCTAssertTrue(ICloudMediaPolicy.fileIsSecret(Array(token.utf8)))
        XCTAssertTrue(ICloudMediaPolicy.documentIsSecret(Array("{\"botToken\":\"x\"}".utf8)))
        XCTAssertTrue(ICloudMediaPolicy.documentIsSecret(Array("{\"passphrase\":\"x\"}".utf8)))
        XCTAssertFalse(ICloudMediaPolicy.fileIsSecret([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertFalse(ICloudMediaPolicy.documentIsSecret(Array(#"{"schemaVersion":2,"loads":[]}"#.utf8)))

        var photo = item(path: "a.jpg", hash: "abc", modifiedAt: 1)
        photo.caption = "shot \(token)"
        photo.ocrText = "page \(token)"
        let manifest = ICloudMediaPolicy.encode(
            ICloudMediaPolicy.Manifest(accountId: "local_dev", updatedAt: 1, items: [photo])
        )
        XCTAssertFalse(manifest.contains(token))
        XCTAssertFalse(manifest.contains("botToken"))
        XCTAssertFalse(manifest.contains("passphrase"))
        XCTAssertFalse(manifest.contains("telegramToken"))

        let nested = ICloudMediaPolicy.canonicalRelativePath(kind: "photo", fileName: "../secret.jpg")
        XCTAssertEqual(nested, "photos/secret.jpg")
        XCTAssertNil(ICloudMediaPolicy.canonicalRelativePath(kind: "receipt", fileName: "a.jpg"))
        XCTAssertEqual(ICloudMediaPolicy.contentHash(Array("a".utf8)), "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb")
    }

    func testHeavyUploadWaitsForPowerAndWifi() {
        XCTAssertEqual(ICloudMediaPolicy.backgroundTaskIdentifier, "com.truckorig.icloud-media")
        XCTAssertTrue(ICloudMediaPolicy.mediaEnabledByDefault)
        XCTAssertTrue(ICloudMediaPolicy.wifiOnlyByDefault)
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(background: true, wifi: true, power: false)),
            .uploadNow
        )
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(background: true, wifi: false, power: false)),
            .skipWifi
        )
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(background: true, wifi: true, power: true)),
            .skipLowPower
        )
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(background: true, wifi: false, power: false, wifiOnly: false)),
            .uploadNow
        )
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(user: true, wifi: true, power: true)),
            .deferToBackground
        )
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(user: true, wifi: false, power: false)),
            .skipWifi
        )
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(user: true, wifi: true, power: false)),
            .uploadNow
        )
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(user: false, wifi: true, power: false)),
            .deferToBackground
        )
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(availability: .signedOut, user: true, wifi: true, power: false)),
            .unavailable
        )
        XCTAssertEqual(
            ICloudMediaPolicy.gate(conditions(enabled: false, user: true, wifi: true, power: false)),
            .skipDisabled
        )
    }

    private func item(
        path: String,
        kind: String = ICloudMediaPolicy.Kind.photo,
        hash: String,
        modifiedAt: Int64,
        city: String = ""
    ) -> ICloudMediaPolicy.Item {
        ICloudMediaPolicy.Item(
            recordId: "rec-\(path)",
            kind: kind,
            fileName: path,
            relativePath: ICloudMediaPolicy.canonicalRelativePath(kind: kind, fileName: path) ?? path,
            contentHash: hash,
            byteCount: Int64(hash.count + 1),
            modifiedAt: modifiedAt,
            loadId: "11111111-1111-1111-1111-111111111111",
            tripId: "T-1",
            city: city,
            timestampMillis: 1_700_000_000_000
        )
    }

    private func conditions(
        availability: ICloudBackupPolicy.Availability = .available,
        enabled: Bool = true,
        user: Bool = false,
        background: Bool = false,
        wifi: Bool,
        power: Bool,
        wifiOnly: Bool = true
    ) -> ICloudMediaPolicy.Conditions {
        ICloudMediaPolicy.Conditions(
            availability: availability,
            mediaEnabled: enabled,
            wifiOnly: wifiOnly,
            onWifi: wifi,
            lowPowerMode: power,
            userRequested: user,
            backgroundTask: background
        )
    }
}
