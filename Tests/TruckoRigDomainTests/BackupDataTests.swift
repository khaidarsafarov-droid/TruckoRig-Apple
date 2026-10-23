import XCTest
@testable import TruckoRigDomain

/// Gson 2.11 output for the Android round-trip fixture (`BackupTestFixtures` + `BackupDataCodec`).
/// Field order, omitted nulls, unboxed `Money`, and boxed nullable `Money` / `UnitPrice` are significant.
private let gsonFixture = #"{"schemaVersion":2,"version":2,"exportedAt":1721570000000,"accountId":"user-abc","loads":[{"id":"L-ROUNDTRIP","tripId":"T-116KYL6KW","date":"2026-07-21","totalRate":250000,"totalMiles":850.0,"pointA":"Garner, NC","pointB":"Dallas, TX","puCount":1,"delCount":1,"weekNumber":30,"year":2026,"rawMessage":"Trip ID: T-116KYL6KW","parsedAt":1721548800000,"updatedAt":1721552400000,"route":"","firstPuCityState":"","lastDelCityState":"","durationDays":1.5,"pace":166667,"stopCount":0,"isDispute":false,"disputeCompleted":false,"disputeApplyToLoad":false,"disputeAmountApplied":false,"actualFinishDate":"2026-07-22 18:00","stops":[{"id":11,"loadId":"L-ROUNDTRIP","stopNumber":1,"type":"PU","puNumber":"PU-1","note":"gate 4","scheduledTime":"","timezone":"EDT","facilityCode":"SWF2","fullAddress":"SWF2, Garner, NC","city":"Garner","state":"NC","zip":"27529"},{"id":12,"loadId":"L-ROUNDTRIP","stopNumber":2,"type":"DEL","scheduledTime":"","timezone":"CDT","facilityCode":"DFW9","fullAddress":"Dallas, TX","city":"Dallas","state":"TX","zip":"75201"}],"penalties":[{"id":21,"loadId":"L-ROUNDTRIP","description":"layover","amount":15000}],"equipmentType":"DRY_VAN","deadheadMiles":0.0}],"paychecks":[{"id":31,"weekNumber":30,"year":2026,"weekLabel":"Week 30","weekStartDate":"2026-07-20","weekEndDate":"2026-07-26","driverName":"Test Driver","grossAmount":{"cents":320000},"netAmount":280000,"rawExtractedText":"gross 3200","sourceFileName":"pay.pdf","addedAt":1721560000000}],"diesel":[{"id":41,"weekNumber":30,"year":2026,"weekLabel":"Week 30","weekStartDate":"2026-07-20","weekEndDate":"2026-07-26","totalAmount":54025,"gallons":120.0,"pricePerGallon":{"thousandths":4502},"location":"Pilot, NC","rawExtractedText":"diesel 540.25","sourceFileName":"fuel.jpg","addedAt":1721560000000}],"maintenanceTasks":[{"id":7,"title":"Oil change","startDate":"2026-01-01","reminderType":"MILES","intervalMiles":15000.0,"odometerAtStart":120000.0,"isCompleted":false,"createdAt":1,"updatedAt":2}],"maintenanceArchive":[{"id":8,"serviceName":"Oil","serviceDate":"2025-12-01","description":"full synthetic","amount":89.0,"createdAt":3}],"appSettings":{"themeModeOrdinal":1,"languageOrdinal":0,"weeklyProfitGoal":4500.0,"rpmMinProfit":2.0,"rpmTargetProfit":2.5,"loadWeekStartDay":2,"dieselWeekStartDay":1}}"#

final class BackupDataTests: XCTestCase {

    func testGsonFixtureRoundTripsByteForByte() throws {
        let decoded = try BackupDataCodec.decode(gsonFixture)
        XCTAssertEqual(decoded.loads[0].totalRateCents, 250_000)
        XCTAssertEqual(decoded.loads[0].paceCents, 166_667)
        XCTAssertEqual(decoded.loads[0].stopCount, 0)
        XCTAssertEqual(decoded.loads[0].stops[1].puNumber, nil)
        XCTAssertEqual(decoded.paychecks[0].grossAmountCents, 320_000)
        XCTAssertEqual(decoded.paychecks[0].netAmountCents, 280_000)
        XCTAssertNil(decoded.paychecks[0].sourceFilePath)
        XCTAssertEqual(decoded.diesel[0].pricePerGallonThousandths, 4_502)
        XCTAssertNil(decoded.diesel[0].discountPricePerGallonThousandths)
        XCTAssertEqual(decoded.maintenanceTasks[0].id, 7)
        XCTAssertEqual(decoded.maintenanceArchive[0].amount, 89)
        XCTAssertEqual(decoded.appSettings?.loadWeekStartDay, 2)
        XCTAssertEqual(decoded.appSettings?.dieselWeekStartDay, 1)
        XCTAssertNil(decoded.appSettings?.telegramChatId)
        XCTAssertEqual(BackupDataCodec.encode(decoded), gsonFixture)
    }

    func testMoneyAcceptsANumberOrACentsObject() throws {
        let number = #"{"schemaVersion":2,"loads":[{"id":"L","totalRate":250000,"disputeAmount":{"cents":15000},"penalties":[{"amount":{"cents":9}}]}]}"#
        let backup = try BackupDataCodec.decode(number)
        XCTAssertEqual(backup.loads[0].totalRateCents, 250_000)
        XCTAssertEqual(backup.loads[0].disputeAmountCents, 15_000)
        XCTAssertEqual(backup.loads[0].penalties[0].amountCents, 9)
    }

    func testLegacyVersionAndMissingVersionResolveToV1() throws {
        let versionOnly = try BackupDataCodec.decode(#"{"version":1,"maintenanceTasks":[]}"#)
        XCTAssertEqual(versionOnly.schemaVersion, 1)
        XCTAssertEqual(versionOnly.version, 1)
        XCTAssertFalse(BackupDataCodec.carriesMaintenance(versionOnly))

        let missing = try BackupDataCodec.decode(#"{"loads":[]}"#)
        XCTAssertEqual(missing.schemaVersion, BackupSchema.v1)
        XCTAssertFalse(BackupDataCodec.carriesMaintenance(missing))
    }

    func testBomIsStrippedAndGarbageIsRejected() throws {
        let bom = "\u{FEFF}" + #"{"schemaVersion":2,"loads":[]}"#
        let decoded = try BackupDataCodec.decode(bom)
        XCTAssertEqual(decoded.schemaVersion, 2)

        XCTAssertThrowsError(try BackupDataCodec.decode("")) { error in
            XCTAssertEqual(error as? BackupDecodeError, .invalidFormat)
        }
        XCTAssertThrowsError(try BackupDataCodec.decode("   ")) { error in
            XCTAssertEqual(error as? BackupDecodeError, .invalidFormat)
        }
        XCTAssertThrowsError(try BackupDataCodec.decode("not-json")) { error in
            XCTAssertEqual(error as? BackupDecodeError, .corrupted)
        }
        XCTAssertThrowsError(try BackupDataCodec.decode("[]")) { error in
            XCTAssertEqual(error as? BackupDecodeError, .corrupted)
        }
        XCTAssertThrowsError(try BackupDataCodec.decode(#"{"schemaVersion":99}"#)) { error in
            XCTAssertEqual(error as? BackupDecodeError, .schemaTooNew(99))
        }
    }

    func testTelegramChatIdIsReadAndNeverWritten() throws {
        let decoded = try BackupDataCodec.decode(#"{"schemaVersion":2,"appSettings":{"telegramChatId":42,"languageOrdinal":0}}"#)
        XCTAssertEqual(decoded.appSettings?.telegramChatId, 42)
        let encoded = BackupDataCodec.encode(decoded)
        XCTAssertFalse(encoded.contains("telegram"))
        XCTAssertTrue(encoded.contains("\"languageOrdinal\":0"))
    }

    func testSettingsAloneAreNotABackupAndV2CarriesMaintenance() {
        let settingsOnly = BackupData(schemaVersion: 2, version: 2, appSettings: BackupAppSettings(languageOrdinal: 0))
        XCTAssertFalse(BackupDataCodec.hasExportableContent(settingsOnly))
        XCTAssertTrue(BackupDataCodec.carriesMaintenance(settingsOnly))
        let withLoad = BackupData(loads: [BackupLoad(id: "L")])
        XCTAssertTrue(BackupDataCodec.hasExportableContent(withLoad))
    }

    func testRestoreReplacesJournalAndKeepsV1Maintenance() {
        let existing = BackupJournal(
            loads: [BackupLoad(id: "old")],
            paychecks: [BackupPaycheck(id: 1)],
            diesel: [BackupDiesel(id: 2)],
            maintenanceTasks: [BackupMaintenanceTask(id: 9, title: "keep", startDate: "2026-01-01")],
            maintenanceArchive: [BackupMaintenanceArchive(id: 4, serviceDate: "2026-01-02")],
            appSettings: BackupAppSettings(languageOrdinal: 1)
        )
        let v1 = BackupData(
            schemaVersion: 1,
            version: 1,
            accountId: "local_dev",
            loads: [BackupLoad(id: "new")],
            paychecks: [],
            diesel: [],
            maintenanceTasks: [],
            maintenanceArchive: [],
            appSettings: nil
        )
        guard case .replaced(let kept) = BackupDataCodec.restore(
            v1,
            onto: existing,
            activeAccountId: "local_dev",
            allowUnboundAccount: false
        ) else {
            return XCTFail("expected replace")
        }
        XCTAssertEqual(kept.loads.map(\.id), ["new"])
        XCTAssertTrue(kept.paychecks.isEmpty)
        XCTAssertTrue(kept.diesel.isEmpty)
        XCTAssertEqual(kept.maintenanceTasks.map(\.id), [9])
        XCTAssertEqual(kept.maintenanceArchive.map(\.id), [4])
        XCTAssertEqual(kept.appSettings?.languageOrdinal, 1)

        let v2 = BackupData(
            schemaVersion: 2,
            version: 2,
            accountId: "local_dev",
            maintenanceTasks: [],
            maintenanceArchive: [],
            appSettings: BackupAppSettings(weeklyProfitGoal: 10)
        )
        guard case .replaced(let wiped) = BackupDataCodec.restore(
            v2,
            onto: existing,
            activeAccountId: "local_dev",
            allowUnboundAccount: false
        ) else {
            return XCTFail("expected replace")
        }
        XCTAssertTrue(wiped.maintenanceTasks.isEmpty)
        XCTAssertTrue(wiped.maintenanceArchive.isEmpty)
        XCTAssertEqual(wiped.appSettings?.weeklyProfitGoal, 10)
    }

    func testRestoreRejectsWrongAndUnboundAccounts() {
        let journal = BackupJournal(loads: [BackupLoad(id: "stay")])
        let foreign = BackupData(schemaVersion: 2, version: 2, accountId: "google_other", loads: [BackupLoad(id: "x")])
        XCTAssertEqual(
            BackupDataCodec.restore(foreign, onto: journal, activeAccountId: "local_dev", allowUnboundAccount: true),
            .rejected(.wrongAccount)
        )

        let unbound = BackupData(schemaVersion: 2, version: 2, accountId: "  ", loads: [BackupLoad(id: "x")])
        XCTAssertEqual(
            BackupDataCodec.restore(unbound, onto: journal, activeAccountId: "local_dev", allowUnboundAccount: false),
            .rejected(.unboundAccount)
        )
        guard case .replaced(let replaced) = BackupDataCodec.restore(
            unbound,
            onto: journal,
            activeAccountId: "local_dev",
            allowUnboundAccount: true
        ) else {
            return XCTFail("unbound allowed")
        }
        XCTAssertEqual(replaced.loads.map(\.id), ["x"])
        XCTAssertTrue(BackupDataCodec.exceedsRestoreLimit(byteCount: BackupSchedule.maxRestoreBytes + 1))
        XCTAssertFalse(BackupDataCodec.exceedsRestoreLimit(byteCount: BackupSchedule.maxRestoreBytes))
    }

    func testAccountSanitizerAndManualFileName() {
        XCTAssertEqual(BackupAccount.localDev, "local_dev")
        XCTAssertEqual(BackupAccount.sanitizeFilePart("  google user/1  "), "google_user_1")
        XCTAssertEqual(BackupAccount.sanitizeFilePart("   "), "unknown")
        XCTAssertEqual(BackupAccount.sanitizeFilePart(String(repeating: "a", count: 90)).count, 80)
        XCTAssertEqual(
            BackupAccount.identitySuiteName(accountId: "local_dev"),
            "truckorig.backup.local_dev.identity"
        )
        XCTAssertEqual(BackupSchema.filePrefix, "TruckoRig")
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(
            BackupSchema.jsonFileName(exportedAt: 1_721_570_000_000, timeZone: utc),
            "TruckoRig_Backup_20240721_135320.json"
        )
    }
}

final class BackupSyncPolicyTests: XCTestCase {

    func testSkipAndWarnUseTheTwoSecondSkew() {
        XCTAssertFalse(BackupSyncPolicy.shouldSkipAutoPush(remoteModifiedAt: 0, lastSyncAt: 5_000))
        XCTAssertTrue(BackupSyncPolicy.shouldSkipAutoPush(remoteModifiedAt: 5_000, lastSyncAt: 0))
        XCTAssertTrue(BackupSyncPolicy.shouldSkipAutoPush(remoteModifiedAt: 8_001, lastSyncAt: 6_000))
        XCTAssertFalse(BackupSyncPolicy.shouldSkipAutoPush(remoteModifiedAt: 8_000, lastSyncAt: 6_000))
        XCTAssertFalse(BackupSyncPolicy.remoteIsNewer(remoteModifiedAt: 8_000, lastSyncAt: 6_000))
        XCTAssertTrue(BackupSyncPolicy.remoteIsNewer(remoteModifiedAt: 8_001, lastSyncAt: 6_000))

        XCTAssertFalse(BackupSyncPolicy.shouldWarnBeforeRestore(
            localChangedAfterLastSync: false,
            remoteModifiedAt: 9_000,
            lastSyncAt: 1
        ))
        XCTAssertTrue(BackupSyncPolicy.shouldWarnBeforeRestore(
            localChangedAfterLastSync: true,
            remoteModifiedAt: 0,
            lastSyncAt: 0
        ))
        XCTAssertTrue(BackupSyncPolicy.shouldWarnBeforeRestore(
            localChangedAfterLastSync: true,
            remoteModifiedAt: 9_000,
            lastSyncAt: 1_000
        ))
        XCTAssertFalse(BackupSyncPolicy.shouldWarnBeforeRestore(
            localChangedAfterLastSync: true,
            remoteModifiedAt: 1_000,
            lastSyncAt: 9_000
        ))
    }

    func testLocalDirtyLooksOnlyAtLoads() {
        XCTAssertFalse(BackupSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [], parsedAt: [], lastSyncAt: 0))
        XCTAssertTrue(BackupSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [10], parsedAt: [10], lastSyncAt: 0))
        XCTAssertTrue(BackupSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [50], parsedAt: [10], lastSyncAt: 40))
        XCTAssertTrue(BackupSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [10], parsedAt: [50], lastSyncAt: 40))
        XCTAssertFalse(BackupSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [10], parsedAt: [20], lastSyncAt: 40))
    }

    func testRetryClassificationAndBackoff() {
        XCTAssertEqual(BackupSyncPolicy.backoffDelayMs(attemptIndex: 0), 400)
        XCTAssertEqual(BackupSyncPolicy.backoffDelayMs(attemptIndex: 1), 800)
        XCTAssertEqual(BackupSyncPolicy.backoffDelayMs(attemptIndex: 2), 1_200)
        XCTAssertFalse(BackupSyncPolicy.isRetryableFailure("Not signed in to Google Drive"))
        XCTAssertFalse(BackupSyncPolicy.isRetryableFailure("consent"))
        XCTAssertFalse(BackupSyncPolicy.isRetryableFailure("List failed (401): nope"))
        XCTAssertTrue(BackupSyncPolicy.isRetryableFailure("List failed (404): missing"))
        XCTAssertTrue(BackupSyncPolicy.isRetryableFailure("timeout"))
        XCTAssertTrue(BackupSyncPolicy.isRetryableFailure("Download failed (503)"))
        XCTAssertTrue(BackupSyncPolicy.isRetryableFailure("unable to resolve host"))
        XCTAssertTrue(BackupSyncPolicy.isRetryableFailure("connection"))
    }

    func testEligibility() {
        XCTAssertFalse(BackupSyncEligibility.shouldEnqueuePeriodic(userId: nil))
        XCTAssertFalse(BackupSyncEligibility.shouldEnqueuePeriodic(userId: "  "))
        XCTAssertTrue(BackupSyncEligibility.shouldEnqueuePeriodic(userId: "local_dev"))
    }

    func testAutoPushAndPeriodicResult() {
        XCTAssertEqual(BackupSchedule.periodicIntervalSeconds, 12 * 60 * 60)
        XCTAssertEqual(BackupSchedule.autoBackupDebounceSeconds, 45)
        XCTAssertTrue(BackupSchedule.requiresNetwork)
        XCTAssertFalse(BackupSchedule.requiresExternalPower)
        XCTAssertEqual(BackupSchedule.maxRestoreBytes, 32 * 1024 * 1024)

        XCTAssertEqual(BackupSchedule.autoPush(
            clientConfigured: false,
            autoSyncEnabled: true,
            isLinked: true,
            scopeGranted: true,
            remoteProbeFailed: false,
            remoteExists: false,
            remoteModifiedAt: 0,
            lastSyncAt: 0,
            hasExportableContent: true
        ), .skip)
        XCTAssertEqual(BackupSchedule.autoPush(
            clientConfigured: true,
            autoSyncEnabled: false,
            isLinked: true,
            scopeGranted: true,
            remoteProbeFailed: false,
            remoteExists: false,
            remoteModifiedAt: 0,
            lastSyncAt: 0,
            hasExportableContent: true
        ), .skip)
        XCTAssertEqual(BackupSchedule.autoPush(
            clientConfigured: true,
            autoSyncEnabled: true,
            isLinked: false,
            scopeGranted: false,
            remoteProbeFailed: false,
            remoteExists: false,
            remoteModifiedAt: 0,
            lastSyncAt: 0,
            hasExportableContent: true
        ), .skip)
        XCTAssertEqual(BackupSchedule.autoPush(
            clientConfigured: true,
            autoSyncEnabled: true,
            isLinked: true,
            scopeGranted: true,
            remoteProbeFailed: true,
            remoteExists: false,
            remoteModifiedAt: 0,
            lastSyncAt: 0,
            hasExportableContent: true
        ), .metadataUnavailable)
        XCTAssertEqual(BackupSchedule.autoPush(
            clientConfigured: true,
            autoSyncEnabled: true,
            isLinked: true,
            scopeGranted: true,
            remoteProbeFailed: false,
            remoteExists: true,
            remoteModifiedAt: 9_000,
            lastSyncAt: 0,
            hasExportableContent: true
        ), .skip)
        XCTAssertEqual(BackupSchedule.autoPush(
            clientConfigured: true,
            autoSyncEnabled: true,
            isLinked: true,
            scopeGranted: true,
            remoteProbeFailed: false,
            remoteExists: false,
            remoteModifiedAt: 0,
            lastSyncAt: 0,
            hasExportableContent: false
        ), .skip)
        XCTAssertEqual(BackupSchedule.autoPush(
            clientConfigured: true,
            autoSyncEnabled: true,
            isLinked: false,
            scopeGranted: true,
            remoteProbeFailed: false,
            remoteExists: false,
            remoteModifiedAt: 0,
            lastSyncAt: 1,
            hasExportableContent: true
        ), .upload)

        XCTAssertEqual(BackupSchedule.periodicResult(userId: " ", pushSucceeded: false), .success)
        XCTAssertEqual(BackupSchedule.periodicResult(userId: "local_dev", pushSucceeded: false), .retry)
        XCTAssertEqual(BackupSchedule.periodicResult(userId: "local_dev", pushSucceeded: true), .success)
    }
}

/// Android `BackupTestFixtures.sampleLoad` / `samplePaycheck` / `sampleDiesel`, plus the
/// maintenance and settings rows from `BackupDataCodecTest.roundTrip_preservesMaintenanceAndAppSettings`
/// (week start is `Calendar.MONDAY` = 2 and `Calendar.SUNDAY` = 1). Nulls stay omitted, matching Gson.
private func androidSampleBackup() -> BackupData {
    BackupData(
        schemaVersion: BackupSchema.current,
        version: BackupSchema.current,
        exportedAt: 1_721_570_000_000,
        accountId: "user-abc",
        loads: [
            BackupLoad(
                id: "L-ROUNDTRIP",
                tripId: "T-116KYL6KW",
                date: "2026-07-21",
                totalRateCents: 250_000,
                totalMiles: 850,
                pointA: "Garner, NC",
                pointB: "Dallas, TX",
                puCount: 1,
                delCount: 1,
                weekNumber: 30,
                year: 2026,
                rawMessage: "Trip ID: T-116KYL6KW",
                parsedAt: 1_721_548_800_000,
                updatedAt: 1_721_552_400_000,
                durationDays: 1.5,
                paceCents: 166_667,
                actualFinishDate: "2026-07-22 18:00",
                stops: [
                    BackupStop(
                        id: 11,
                        loadId: "L-ROUNDTRIP",
                        stopNumber: 1,
                        type: "PU",
                        puNumber: "PU-1",
                        note: "gate 4",
                        timezone: "EDT",
                        facilityCode: "SWF2",
                        fullAddress: "SWF2, Garner, NC",
                        city: "Garner",
                        state: "NC",
                        zip: "27529"
                    ),
                    BackupStop(
                        id: 12,
                        loadId: "L-ROUNDTRIP",
                        stopNumber: 2,
                        type: "DEL",
                        timezone: "CDT",
                        facilityCode: "DFW9",
                        fullAddress: "Dallas, TX",
                        city: "Dallas",
                        state: "TX",
                        zip: "75201"
                    ),
                ],
                penalties: [
                    BackupPenalty(id: 21, loadId: "L-ROUNDTRIP", description: "layover", amountCents: 15_000),
                ],
                equipmentType: "DRY_VAN"
            ),
        ],
        paychecks: [
            BackupPaycheck(
                id: 31,
                weekNumber: 30,
                year: 2026,
                weekLabel: "Week 30",
                weekStartDate: "2026-07-20",
                weekEndDate: "2026-07-26",
                driverName: "Test Driver",
                grossAmountCents: 320_000,
                netAmountCents: 280_000,
                rawExtractedText: "gross 3200",
                sourceFileName: "pay.pdf",
                addedAt: 1_721_560_000_000
            ),
        ],
        diesel: [
            BackupDiesel(
                id: 41,
                weekNumber: 30,
                year: 2026,
                weekLabel: "Week 30",
                weekStartDate: "2026-07-20",
                weekEndDate: "2026-07-26",
                totalAmountCents: 54_025,
                gallons: 120,
                pricePerGallonThousandths: 4_502,
                location: "Pilot, NC",
                rawExtractedText: "diesel 540.25",
                sourceFileName: "fuel.jpg",
                addedAt: 1_721_560_000_000
            ),
        ],
        maintenanceTasks: [
            BackupMaintenanceTask(
                id: 7,
                title: "Oil change",
                startDate: "2026-01-01",
                reminderType: "MILES",
                intervalMiles: 15_000,
                odometerAtStart: 120_000,
                createdAt: 1,
                updatedAt: 2
            ),
        ],
        maintenanceArchive: [
            BackupMaintenanceArchive(
                id: 8,
                serviceName: "Oil",
                serviceDate: "2025-12-01",
                description: "full synthetic",
                amount: 89,
                createdAt: 3
            ),
        ],
        appSettings: BackupAppSettings(
            themeModeOrdinal: 1,
            languageOrdinal: 0,
            weeklyProfitGoal: 4500,
            rpmMinProfit: 2,
            rpmTargetProfit: 2.5,
            loadWeekStartDay: 2,
            dieselWeekStartDay: 1
        )
    )
}

final class BackupFileFormatTests: XCTestCase {

    func testBuiltAndroidFixtureMatchesGsonBytes() throws {
        let built = androidSampleBackup()
        XCTAssertEqual(BackupDataCodec.encode(built), gsonFixture)
        XCTAssertEqual(try BackupDataCodec.decode(gsonFixture), built)
    }

    func testUtf8BomRoundTripAndNewerSchemaRejection() throws {
        var bytes = Data([0xEF, 0xBB, 0xBF])
        bytes.append(contentsOf: Data(gsonFixture.utf8))
        let json = try BackupRestoreParser.parseToJSON(bytes)
        XCTAssertFalse(json.hasPrefix("\u{FEFF}"))
        let decoded = try BackupDataCodec.decode(json)
        XCTAssertEqual(decoded, androidSampleBackup())

        let newer = #"{"schemaVersion":99,"version":99,"exportedAt":1,"loads":[]}"#
        var newerBytes = Data([0xEF, 0xBB, 0xBF])
        newerBytes.append(contentsOf: Data(newer.utf8))
        let newerJSON = try BackupRestoreParser.parseToJSON(newerBytes)
        XCTAssertThrowsError(try BackupDataCodec.decode(newerJSON)) { error in
            XCTAssertEqual(error as? BackupDecodeError, .schemaTooNew(99))
        }
    }

    func testChartNoteIsRejectedAndEmbeddedJsonIsAccepted() throws {
        let chart = Data("21.07.2026 | T-1 | $2,500.00 | Garner -> Dallas".utf8)
        XCTAssertThrowsError(try BackupRestoreParser.parseToJSON(chart)) { error in
            XCTAssertEqual(error as? BackupParseFailure, .chartNote)
        }
        XCTAssertThrowsError(try BackupRestoreParser.parseToJSON(Data("hello".utf8))) { error in
            XCTAssertEqual(error as? BackupParseFailure, .invalidFormat)
        }
        let embedded = """
        Visible note
        -----BEGIN TRUCKERLOAD BACKUP-----
        {"version":1,"exportedAt":1,"loads":[]}
        -----END TRUCKERLOAD BACKUP-----
        """
        let json = try BackupRestoreParser.parseToJSON(Data(embedded.utf8))
        let decoded = try BackupDataCodec.decode(json)
        XCTAssertEqual(decoded.schemaVersion, BackupSchema.v1)
        XCTAssertTrue(decoded.loads.isEmpty)
    }

    func testFileRestoreWarnsOnlyWhenLocalJournalIsNewer() {
        XCTAssertFalse(BackupSyncPolicy.shouldWarnBeforeFileRestore(localNewestMillis: 0, backupExportedAt: 10))
        XCTAssertFalse(BackupSyncPolicy.shouldWarnBeforeFileRestore(localNewestMillis: 10, backupExportedAt: 20))
        XCTAssertTrue(BackupSyncPolicy.shouldWarnBeforeFileRestore(localNewestMillis: 20, backupExportedAt: 10))
        XCTAssertTrue(BackupSyncPolicy.shouldWarnBeforeFileRestore(localNewestMillis: 5, backupExportedAt: 0))
    }
}

