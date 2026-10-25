import XCTest
@testable import TruckoRigDomain

final class ICloudBackupPolicyTests: XCTestCase {

    func testNewerExportedAtWinsAndOlderCopyIsNotSilent() {
        XCTAssertEqual(
            ICloudBackupPolicy.resolution(localNewestMillis: 100, remoteExportedAt: nil, lastUploadedExportedAt: 0),
            .uploadLocal
        )
        XCTAssertEqual(
            ICloudBackupPolicy.resolution(localNewestMillis: 500, remoteExportedAt: 100, lastUploadedExportedAt: 0),
            .uploadLocal
        )
        XCTAssertEqual(
            ICloudBackupPolicy.resolution(localNewestMillis: 100, remoteExportedAt: 500, lastUploadedExportedAt: 0),
            .keepRemote
        )
        XCTAssertEqual(
            ICloudBackupPolicy.resolution(localNewestMillis: 100, remoteExportedAt: 100, lastUploadedExportedAt: 100),
            .inSync
        )
        XCTAssertEqual(
            ICloudBackupPolicy.resolution(localNewestMillis: 50, remoteExportedAt: 80, lastUploadedExportedAt: 200),
            .uploadLocal
        )

        XCTAssertEqual(
            ICloudBackupPolicy.applyBlock(
                confirmed: false,
                localNewestMillis: 500,
                remoteExportedAt: 100,
                fileAccountId: "local_dev",
                activeAccountId: "local_dev"
            ),
            .olderThanLocal
        )
        XCTAssertNil(ICloudBackupPolicy.applyBlock(
            confirmed: true,
            localNewestMillis: 500,
            remoteExportedAt: 100,
            fileAccountId: "local_dev",
            activeAccountId: "local_dev"
        ))
        XCTAssertEqual(
            ICloudBackupPolicy.applyBlock(
                confirmed: false,
                localNewestMillis: 0,
                remoteExportedAt: 100,
                fileAccountId: "local_dev",
                activeAccountId: "local_dev"
            ),
            .needsConfirmation
        )
    }

    func testForeignAccountNeedsConfirmationAndSchemaStaysStrict() throws {
        XCTAssertEqual(
            ICloudBackupPolicy.applyBlock(
                confirmed: false,
                localNewestMillis: 0,
                remoteExportedAt: 10,
                fileAccountId: "google_user",
                activeAccountId: BackupAccount.localDev
            ),
            .foreignAccount
        )
        XCTAssertNil(ICloudBackupPolicy.applyBlock(
            confirmed: true,
            localNewestMillis: 0,
            remoteExportedAt: 10,
            fileAccountId: "google_user",
            activeAccountId: BackupAccount.localDev
        ))
        XCTAssertEqual(
            ICloudBackupPolicy.applyBlock(
                confirmed: false,
                localNewestMillis: 0,
                remoteExportedAt: 10,
                fileAccountId: "  ",
                activeAccountId: BackupAccount.localDev
            ),
            .unboundAccount
        )

        let journal = BackupJournal(loads: [BackupLoad(id: "stay")])
        let foreign = BackupData(
            schemaVersion: 2,
            version: 2,
            accountId: "google_user",
            loads: [BackupLoad(id: "x")]
        )
        XCTAssertEqual(
            BackupDataCodec.restore(
                foreign,
                onto: journal,
                activeAccountId: BackupAccount.localDev,
                allowUnboundAccount: true
            ),
            .rejected(.wrongAccount)
        )
        guard case .replaced(let replaced) = BackupDataCodec.restore(
            foreign,
            onto: journal,
            activeAccountId: BackupAccount.localDev,
            allowUnboundAccount: true,
            allowForeignAccount: true
        ) else {
            return XCTFail("confirmed foreign account should restore")
        }
        XCTAssertEqual(replaced.loads.map(\.id), ["x"])

        XCTAssertThrowsError(try BackupDataCodec.decode(#"{"schemaVersion":99,"loads":[]}"#)) { error in
            XCTAssertEqual(error as? BackupDecodeError, .schemaTooNew(99))
        }
        let bom = "\u{FEFF}" + #"{"schemaVersion":2,"exportedAt":42,"loads":[]}"#
        XCTAssertEqual(try BackupDataCodec.decode(bom).exportedAt, 42)
    }

    func testOriginFieldsRoundTripAndStayOffTheManualFile() throws {
        let plain = BackupData(
            schemaVersion: 2,
            version: 2,
            exportedAt: 42,
            accountId: "local_dev",
            loads: [BackupLoad(id: "L", tripId: "T")]
        )
        let plainJSON = BackupDataCodec.encode(plain)
        XCTAssertFalse(plainJSON.contains("originDevice"))
        XCTAssertFalse(plainJSON.contains("originPlatform"))
        XCTAssertFalse(plainJSON.contains("telegram"))
        XCTAssertFalse(plainJSON.contains("botToken"))

        var stamped = plain
        stamped.originDevice = "iPhone"
        stamped.originPlatform = ICloudBackupPolicy.originPlatformIOS
        let stampedJSON = BackupDataCodec.encode(stamped)
        let decoded = try BackupDataCodec.decode(stampedJSON)
        XCTAssertEqual(decoded.originDevice, "iPhone")
        XCTAssertEqual(decoded.originPlatform, "ios")
        XCTAssertEqual(BackupDataCodec.encode(decoded), stampedJSON)
        XCTAssertFalse(stampedJSON.contains("telegram"))
    }

    func testScheduleAndConflictVersions() {
        XCTAssertEqual(ICloudBackupPolicy.containerIdentifier, "iCloud.com.truckorig")
        XCTAssertEqual(ICloudBackupPolicy.backgroundTaskIdentifier, "com.truckorig.icloud-sync")
        XCTAssertEqual(ICloudBackupPolicy.periodicInterval, 12 * 60 * 60)
        XCTAssertEqual(ICloudBackupPolicy.debounce, 45)
        XCTAssertTrue(ICloudBackupPolicy.requiresNetwork)
        XCTAssertEqual(
            ICloudBackupPolicy.containerFileName(accountId: " google/user "),
            "TruckoRig_Backup_google_user.json"
        )

        let versions = [
            ICloudBackupPolicy.VersionStamp(exportedAt: 10, isCurrent: true),
            ICloudBackupPolicy.VersionStamp(exportedAt: 30, isCurrent: false),
            ICloudBackupPolicy.VersionStamp(exportedAt: 30, isCurrent: false),
        ]
        XCTAssertEqual(ICloudBackupPolicy.winningVersionIndex(versions), 1)
        XCTAssertEqual(
            ICloudBackupPolicy.winningVersionIndex([
                ICloudBackupPolicy.VersionStamp(exportedAt: 5, isCurrent: true),
                ICloudBackupPolicy.VersionStamp(exportedAt: 5, isCurrent: false),
            ]),
            0
        )
        XCTAssertNil(ICloudBackupPolicy.winningVersionIndex([]))

        XCTAssertEqual(ICloudBackupPolicy.autoSync(
            availability: .signedOut,
            autoSyncEnabled: true,
            hasExportableContent: true,
            debounceElapsed: true,
            localNewestMillis: 10,
            remoteExportedAt: nil,
            lastUploadedExportedAt: 0
        ), .unavailable)
        XCTAssertEqual(ICloudBackupPolicy.autoSync(
            availability: .available,
            autoSyncEnabled: true,
            hasExportableContent: true,
            debounceElapsed: false,
            localNewestMillis: 10,
            remoteExportedAt: nil,
            lastUploadedExportedAt: 0
        ), .waitingForDebounce)
        XCTAssertEqual(ICloudBackupPolicy.autoSync(
            availability: .available,
            autoSyncEnabled: true,
            hasExportableContent: false,
            debounceElapsed: true,
            localNewestMillis: 0,
            remoteExportedAt: nil,
            lastUploadedExportedAt: 0
        ), .nothingToUpload)
        XCTAssertEqual(ICloudBackupPolicy.autoSync(
            availability: .available,
            autoSyncEnabled: false,
            hasExportableContent: true,
            debounceElapsed: true,
            localNewestMillis: 10,
            remoteExportedAt: nil,
            lastUploadedExportedAt: 0
        ), .autoOff)
    }
}
