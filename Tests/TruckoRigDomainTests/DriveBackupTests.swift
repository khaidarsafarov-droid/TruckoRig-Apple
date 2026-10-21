import XCTest
@testable import TruckoRigDomain

/// Gson 2.11 output for the Android round-trip fixture (`BackupTestFixtures` + `BackupDataCodec`).
/// Field order, omitted nulls, unboxed `Money`, and boxed nullable `Money` / `UnitPrice` are significant.
private let gsonFixture = #"{"schemaVersion":2,"version":2,"exportedAt":1721570000000,"accountId":"user-abc","loads":[{"id":"L-ROUNDTRIP","tripId":"T-116KYL6KW","date":"2026-07-21","totalRate":250000,"totalMiles":850.0,"pointA":"Garner, NC","pointB":"Dallas, TX","puCount":1,"delCount":1,"weekNumber":30,"year":2026,"rawMessage":"Trip ID: T-116KYL6KW","parsedAt":1721548800000,"updatedAt":1721552400000,"route":"","firstPuCityState":"","lastDelCityState":"","durationDays":1.5,"pace":166667,"stopCount":0,"isDispute":false,"disputeCompleted":false,"disputeApplyToLoad":false,"disputeAmountApplied":false,"actualFinishDate":"2026-07-22 18:00","stops":[{"id":11,"loadId":"L-ROUNDTRIP","stopNumber":1,"type":"PU","puNumber":"PU-1","note":"gate 4","scheduledTime":"","timezone":"EDT","facilityCode":"SWF2","fullAddress":"SWF2, Garner, NC","city":"Garner","state":"NC","zip":"27529"},{"id":12,"loadId":"L-ROUNDTRIP","stopNumber":2,"type":"DEL","scheduledTime":"","timezone":"CDT","facilityCode":"DFW9","fullAddress":"Dallas, TX","city":"Dallas","state":"TX","zip":"75201"}],"penalties":[{"id":21,"loadId":"L-ROUNDTRIP","description":"layover","amount":15000}],"equipmentType":"DRY_VAN","deadheadMiles":0.0}],"paychecks":[{"id":31,"weekNumber":30,"year":2026,"weekLabel":"Week 30","weekStartDate":"2026-07-20","weekEndDate":"2026-07-26","driverName":"Test Driver","grossAmount":{"cents":320000},"netAmount":280000,"rawExtractedText":"gross 3200","sourceFileName":"pay.pdf","addedAt":1721560000000}],"diesel":[{"id":41,"weekNumber":30,"year":2026,"weekLabel":"Week 30","weekStartDate":"2026-07-20","weekEndDate":"2026-07-26","totalAmount":54025,"gallons":120.0,"pricePerGallon":{"thousandths":4502},"location":"Pilot, NC","rawExtractedText":"diesel 540.25","sourceFileName":"fuel.jpg","addedAt":1721560000000}],"maintenanceTasks":[{"id":7,"title":"Oil change","startDate":"2026-01-01","reminderType":"MILES","intervalMiles":15000.0,"odometerAtStart":120000.0,"isCompleted":false,"createdAt":1,"updatedAt":2}],"maintenanceArchive":[{"id":8,"serviceName":"Oil","serviceDate":"2025-12-01","description":"full synthetic","amount":89.0,"createdAt":3}],"appSettings":{"themeModeOrdinal":1,"languageOrdinal":0,"weeklyProfitGoal":4500.0,"rpmMinProfit":2.0,"rpmTargetProfit":2.5,"loadWeekStartDay":2,"dieselWeekStartDay":1}}"#

final class DriveBackupTests: XCTestCase {

    func testGsonFixtureRoundTripsByteForByte() throws {
        let decoded = try DriveBackupCodec.decode(gsonFixture)
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
        XCTAssertEqual(DriveBackupCodec.encode(decoded), gsonFixture)
    }

    func testMoneyAcceptsANumberOrACentsObject() throws {
        let number = #"{"schemaVersion":2,"loads":[{"id":"L","totalRate":250000,"disputeAmount":{"cents":15000},"penalties":[{"amount":{"cents":9}}]}]}"#
        let backup = try DriveBackupCodec.decode(number)
        XCTAssertEqual(backup.loads[0].totalRateCents, 250_000)
        XCTAssertEqual(backup.loads[0].disputeAmountCents, 15_000)
        XCTAssertEqual(backup.loads[0].penalties[0].amountCents, 9)
    }

    func testLegacyVersionAndMissingVersionResolveToV1() throws {
        let versionOnly = try DriveBackupCodec.decode(#"{"version":1,"maintenanceTasks":[]}"#)
        XCTAssertEqual(versionOnly.schemaVersion, 1)
        XCTAssertEqual(versionOnly.version, 1)
        XCTAssertFalse(DriveBackupCodec.carriesMaintenance(versionOnly))

        let missing = try DriveBackupCodec.decode(#"{"loads":[]}"#)
        XCTAssertEqual(missing.schemaVersion, DriveBackupSchema.v1)
        XCTAssertFalse(DriveBackupCodec.carriesMaintenance(missing))
    }

    func testBomIsStrippedAndGarbageIsRejected() throws {
        let bom = "\u{FEFF}" + #"{"schemaVersion":2,"loads":[]}"#
        let decoded = try DriveBackupCodec.decode(bom)
        XCTAssertEqual(decoded.schemaVersion, 2)

        XCTAssertThrowsError(try DriveBackupCodec.decode("")) { error in
            XCTAssertEqual(error as? DriveBackupDecodeError, .invalidFormat)
        }
        XCTAssertThrowsError(try DriveBackupCodec.decode("   ")) { error in
            XCTAssertEqual(error as? DriveBackupDecodeError, .invalidFormat)
        }
        XCTAssertThrowsError(try DriveBackupCodec.decode("not-json")) { error in
            XCTAssertEqual(error as? DriveBackupDecodeError, .corrupted)
        }
        XCTAssertThrowsError(try DriveBackupCodec.decode("[]")) { error in
            XCTAssertEqual(error as? DriveBackupDecodeError, .corrupted)
        }
        XCTAssertThrowsError(try DriveBackupCodec.decode(#"{"schemaVersion":99}"#)) { error in
            XCTAssertEqual(error as? DriveBackupDecodeError, .schemaTooNew(99))
        }
    }

    func testTelegramChatIdIsReadAndNeverWritten() throws {
        let decoded = try DriveBackupCodec.decode(#"{"schemaVersion":2,"appSettings":{"telegramChatId":42,"languageOrdinal":0}}"#)
        XCTAssertEqual(decoded.appSettings?.telegramChatId, 42)
        let encoded = DriveBackupCodec.encode(decoded)
        XCTAssertFalse(encoded.contains("telegram"))
        XCTAssertTrue(encoded.contains("\"languageOrdinal\":0"))
    }

    func testSettingsAloneAreNotABackupAndV2CarriesMaintenance() {
        let settingsOnly = DriveBackup(schemaVersion: 2, version: 2, appSettings: DriveAppSettings(languageOrdinal: 0))
        XCTAssertFalse(DriveBackupCodec.hasExportableContent(settingsOnly))
        XCTAssertTrue(DriveBackupCodec.carriesMaintenance(settingsOnly))
        let withLoad = DriveBackup(loads: [DriveLoad(id: "L")])
        XCTAssertTrue(DriveBackupCodec.hasExportableContent(withLoad))
    }

    func testRestoreReplacesJournalAndKeepsV1Maintenance() {
        let existing = DriveJournal(
            loads: [DriveLoad(id: "old")],
            paychecks: [DrivePaycheck(id: 1)],
            diesel: [DriveDiesel(id: 2)],
            maintenanceTasks: [DriveMaintenanceTask(id: 9, title: "keep", startDate: "2026-01-01")],
            maintenanceArchive: [DriveMaintenanceArchive(id: 4, serviceDate: "2026-01-02")],
            appSettings: DriveAppSettings(languageOrdinal: 1)
        )
        let v1 = DriveBackup(
            schemaVersion: 1,
            version: 1,
            accountId: "local_dev",
            loads: [DriveLoad(id: "new")],
            paychecks: [],
            diesel: [],
            maintenanceTasks: [],
            maintenanceArchive: [],
            appSettings: nil
        )
        guard case .replaced(let kept) = DriveBackupCodec.restore(
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

        let v2 = DriveBackup(
            schemaVersion: 2,
            version: 2,
            accountId: "local_dev",
            maintenanceTasks: [],
            maintenanceArchive: [],
            appSettings: DriveAppSettings(weeklyProfitGoal: 10)
        )
        guard case .replaced(let wiped) = DriveBackupCodec.restore(
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
        let journal = DriveJournal(loads: [DriveLoad(id: "stay")])
        let foreign = DriveBackup(schemaVersion: 2, version: 2, accountId: "google_other", loads: [DriveLoad(id: "x")])
        XCTAssertEqual(
            DriveBackupCodec.restore(foreign, onto: journal, activeAccountId: "local_dev", allowUnboundAccount: true),
            .rejected(.wrongAccount)
        )

        let unbound = DriveBackup(schemaVersion: 2, version: 2, accountId: "  ", loads: [DriveLoad(id: "x")])
        XCTAssertEqual(
            DriveBackupCodec.restore(unbound, onto: journal, activeAccountId: "local_dev", allowUnboundAccount: false),
            .rejected(.unboundAccount)
        )
        guard case .replaced(let replaced) = DriveBackupCodec.restore(
            unbound,
            onto: journal,
            activeAccountId: "local_dev",
            allowUnboundAccount: true
        ) else {
            return XCTFail("unbound allowed")
        }
        XCTAssertEqual(replaced.loads.map(\.id), ["x"])
        XCTAssertTrue(DriveBackupCodec.exceedsRestoreLimit(byteCount: DriveSchedule.maxRestoreBytes + 1))
        XCTAssertFalse(DriveBackupCodec.exceedsRestoreLimit(byteCount: DriveSchedule.maxRestoreBytes))
    }

    func testAccountFileNameMatchesAndroidSanitizer() {
        XCTAssertEqual(DriveAccount.localDev, "local_dev")
        XCTAssertEqual(DriveAccount.backupFileName(accountId: "local_dev"), "truckerload_backup_local_dev.tlb")
        XCTAssertEqual(DriveAccount.prefsName(accountId: "local_dev"), "google_drive_backup_local_dev")
        XCTAssertEqual(DriveAccount.sanitizeFilePart("  google user/1  "), "google_user_1")
        XCTAssertEqual(DriveAccount.sanitizeFilePart("   "), "unknown")
        XCTAssertEqual(DriveAccount.sanitizeFilePart(String(repeating: "a", count: 90)).count, 80)
    }
}

final class DriveSyncPolicyTests: XCTestCase {

    func testSkipAndWarnUseTheTwoSecondSkew() {
        XCTAssertFalse(DriveSyncPolicy.shouldSkipAutoPush(remoteModifiedAt: 0, lastSyncAt: 5_000))
        XCTAssertTrue(DriveSyncPolicy.shouldSkipAutoPush(remoteModifiedAt: 5_000, lastSyncAt: 0))
        XCTAssertTrue(DriveSyncPolicy.shouldSkipAutoPush(remoteModifiedAt: 8_001, lastSyncAt: 6_000))
        XCTAssertFalse(DriveSyncPolicy.shouldSkipAutoPush(remoteModifiedAt: 8_000, lastSyncAt: 6_000))
        XCTAssertFalse(DriveSyncPolicy.remoteIsNewer(remoteModifiedAt: 8_000, lastSyncAt: 6_000))
        XCTAssertTrue(DriveSyncPolicy.remoteIsNewer(remoteModifiedAt: 8_001, lastSyncAt: 6_000))

        XCTAssertFalse(DriveSyncPolicy.shouldWarnBeforeRestore(
            localChangedAfterLastSync: false,
            remoteModifiedAt: 9_000,
            lastSyncAt: 1
        ))
        XCTAssertTrue(DriveSyncPolicy.shouldWarnBeforeRestore(
            localChangedAfterLastSync: true,
            remoteModifiedAt: 0,
            lastSyncAt: 0
        ))
        XCTAssertTrue(DriveSyncPolicy.shouldWarnBeforeRestore(
            localChangedAfterLastSync: true,
            remoteModifiedAt: 9_000,
            lastSyncAt: 1_000
        ))
        XCTAssertFalse(DriveSyncPolicy.shouldWarnBeforeRestore(
            localChangedAfterLastSync: true,
            remoteModifiedAt: 1_000,
            lastSyncAt: 9_000
        ))
    }

    func testLocalDirtyLooksOnlyAtLoads() {
        XCTAssertFalse(DriveSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [], parsedAt: [], lastSyncAt: 0))
        XCTAssertTrue(DriveSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [10], parsedAt: [10], lastSyncAt: 0))
        XCTAssertTrue(DriveSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [50], parsedAt: [10], lastSyncAt: 40))
        XCTAssertTrue(DriveSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [10], parsedAt: [50], lastSyncAt: 40))
        XCTAssertFalse(DriveSyncPolicy.hasLocalChangesAfterLastSync(updatedAt: [10], parsedAt: [20], lastSyncAt: 40))
    }

    func testRetryClassificationAndBackoff() {
        XCTAssertEqual(DriveSyncPolicy.backoffDelayMs(attemptIndex: 0), 400)
        XCTAssertEqual(DriveSyncPolicy.backoffDelayMs(attemptIndex: 1), 800)
        XCTAssertEqual(DriveSyncPolicy.backoffDelayMs(attemptIndex: 2), 1_200)
        XCTAssertFalse(DriveSyncPolicy.isRetryableFailure("Not signed in to Google Drive"))
        XCTAssertFalse(DriveSyncPolicy.isRetryableFailure("consent"))
        XCTAssertFalse(DriveSyncPolicy.isRetryableFailure("List failed (401): nope"))
        XCTAssertTrue(DriveSyncPolicy.isRetryableFailure("List failed (404): missing"))
        XCTAssertTrue(DriveSyncPolicy.isRetryableFailure("timeout"))
        XCTAssertTrue(DriveSyncPolicy.isRetryableFailure("Download failed (503)"))
        XCTAssertTrue(DriveSyncPolicy.isRetryableFailure("unable to resolve host"))
        XCTAssertTrue(DriveSyncPolicy.isRetryableFailure("connection"))
    }

    func testEligibilityAndClientIdGate() {
        XCTAssertFalse(DriveSyncEligibility.shouldEnqueuePeriodic(userId: nil))
        XCTAssertFalse(DriveSyncEligibility.shouldEnqueuePeriodic(userId: "  "))
        XCTAssertTrue(DriveSyncEligibility.shouldEnqueuePeriodic(userId: "local_dev"))

        XCTAssertNil(DriveSchedule.validatedClientID(nil))
        XCTAssertNil(DriveSchedule.validatedClientID("  "))
        XCTAssertNil(DriveSchedule.validatedClientID("REPLACE_WITH_IOS_OAUTH_CLIENT_ID.apps.googleusercontent.com"))
        XCTAssertNil(DriveSchedule.validatedClientID("not-a-client"))
        XCTAssertEqual(
            DriveSchedule.validatedClientID(" 123-abc.apps.googleusercontent.com "),
            "123-abc.apps.googleusercontent.com"
        )
    }

    func testAutoPushAndPeriodicResult() {
        XCTAssertEqual(DriveSchedule.periodicIntervalSeconds, 12 * 60 * 60)
        XCTAssertEqual(DriveSchedule.autoBackupDebounceSeconds, 45)
        XCTAssertTrue(DriveSchedule.requiresNetwork)
        XCTAssertFalse(DriveSchedule.requiresExternalPower)
        XCTAssertEqual(DriveSchedule.driveAppDataScope, "https://www.googleapis.com/auth/drive.appdata")
        XCTAssertEqual(DriveSchedule.taskIdentifier, "com.truckorig.drive-sync")

        XCTAssertEqual(DriveSchedule.autoPush(
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
        XCTAssertEqual(DriveSchedule.autoPush(
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
        XCTAssertEqual(DriveSchedule.autoPush(
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
        XCTAssertEqual(DriveSchedule.autoPush(
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
        XCTAssertEqual(DriveSchedule.autoPush(
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
        XCTAssertEqual(DriveSchedule.autoPush(
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
        XCTAssertEqual(DriveSchedule.autoPush(
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

        XCTAssertEqual(DriveSchedule.periodicResult(userId: " ", pushSucceeded: false), .success)
        XCTAssertEqual(DriveSchedule.periodicResult(userId: "local_dev", pushSucceeded: false), .retry)
        XCTAssertEqual(DriveSchedule.periodicResult(userId: "local_dev", pushSucceeded: true), .success)
    }
}

final class DriveConnectTests: XCTestCase {

    func testInterpreterMatchesPlayServicesOutcomes() {
        XCTAssertEqual(
            DriveConnectInterpreter.next(parsed: DriveParsedSignIn(result: .ok), pending: .tokenConsent),
            .retryBackup
        )
        XCTAssertEqual(
            DriveConnectInterpreter.next(parsed: DriveParsedSignIn(result: .canceled), pending: .tokenConsent),
            .cancelled
        )
        XCTAssertEqual(
            DriveConnectInterpreter.next(parsed: DriveParsedSignIn(result: .canceled), pending: .accountPicker),
            .cancelled
        )
        for code in [12_501, 16, 4] {
            XCTAssertEqual(
                DriveConnectInterpreter.next(
                    parsed: DriveParsedSignIn(statusCode: code, result: .canceled),
                    pending: .accountPicker
                ),
                .cancelled
            )
        }
        XCTAssertEqual(
            DriveConnectInterpreter.next(
                parsed: DriveParsedSignIn(statusCode: 10, result: .canceled),
                pending: .accountPicker
            ),
            .failed
        )
        XCTAssertEqual(
            DriveConnectInterpreter.next(
                parsed: DriveParsedSignIn(email: "a@b.c", grantedDriveScope: true, result: .ok),
                pending: .driveConsent
            ),
            .granted
        )
        XCTAssertEqual(
            DriveConnectInterpreter.next(
                parsed: DriveParsedSignIn(email: "a@b.c", result: .ok),
                pending: .accountPicker
            ),
            .requestDriveConsent(email: "a@b.c")
        )
        XCTAssertEqual(
            DriveConnectInterpreter.next(
                parsed: DriveParsedSignIn(email: "a@b.c", result: .ok),
                pending: .driveConsent
            ),
            .failed
        )
        XCTAssertEqual(
            DriveConnectInterpreter.next(parsed: DriveParsedSignIn(result: .ok), pending: .accountPicker),
            .failed
        )
    }

    func testConnectFlowAsksForDriveScopeOnTheSecondStep() async {
        let session = FakeDriveSession()
        session.steps = [
            DriveParsedSignIn(email: "driver@example.com", grantedDriveScope: false, result: .ok),
            DriveParsedSignIn(email: "driver@example.com", grantedDriveScope: true, result: .ok),
        ]
        let outcome = await DriveConnectFlow.connect(session)
        XCTAssertEqual(outcome, .granted)
        XCTAssertEqual(session.calls.count, 2)
        XCTAssertEqual(session.calls[0].requestDriveScope, false)
        XCTAssertNil(session.calls[0].hint)
        XCTAssertEqual(session.calls[1].requestDriveScope, true)
        XCTAssertEqual(session.calls[1].hint, "driver@example.com")
    }

    func testConnectFlowSkipsSignInWhenScopeIsAlreadyGranted() async {
        let session = FakeDriveSession()
        session.email = "driver@example.com"
        session.hasDriveScope = true
        let outcome = await DriveConnectFlow.connect(session)
        XCTAssertEqual(outcome, .granted)
        XCTAssertTrue(session.calls.isEmpty)
    }

    func testConnectFlowStartsAtConsentWhenEmailIsKnown() async {
        let session = FakeDriveSession()
        session.email = "driver@example.com"
        session.steps = [
            DriveParsedSignIn(email: "driver@example.com", grantedDriveScope: true, result: .ok),
        ]
        let outcome = await DriveConnectFlow.connect(session)
        XCTAssertEqual(outcome, .granted)
        XCTAssertEqual(session.calls.count, 1)
        XCTAssertEqual(session.calls[0].requestDriveScope, true)
        XCTAssertEqual(session.calls[0].hint, "driver@example.com")
    }
}

final class DriveHTTPTests: XCTestCase {

    func testListURLUsesJavaFormEncodingAndAppDataFolder() {
        let url = DriveHTTP.listURL(fileName: "truckerload_backup_local_dev.tlb")
        XCTAssertTrue(url.hasPrefix("https://www.googleapis.com/drive/v3/files?"))
        XCTAssertTrue(url.contains("spaces=appDataFolder"))
        XCTAssertTrue(url.contains("pageSize=1"))
        XCTAssertTrue(url.contains("fields=files(id,name,modifiedTime)"))
        XCTAssertTrue(url.contains("q=name%3D%27truckerload_backup_local_dev.tlb%27+and+trashed%3Dfalse"))
        XCTAssertFalse(url.contains("drive.file"))
        XCTAssertEqual(DriveHTTP.formEncode("a b"), "a+b")
        XCTAssertEqual(DriveHTTP.formEncode("a-b_c.d*"), "a-b_c.d*")
    }

    func testMultipartBodyMatchesOkHttpShape() {
        let body = DriveHTTP.multipartRelated(
            boundary: "truckerload_boundary",
            metadataJSON: "{\"name\":\"file.tlb\",\"parents\":[\"appDataFolder\"]}",
            fileJSON: "{\"schemaVersion\":2}"
        )
        let expected = "--truckerload_boundary\r\n"
            + "Content-Type: application/json; charset=UTF-8\r\n\r\n"
            + "{\"name\":\"file.tlb\",\"parents\":[\"appDataFolder\"]}\r\n"
            + "--truckerload_boundary\r\n"
            + "Content-Type: application/json; charset=UTF-8\r\n\r\n"
            + "{\"schemaVersion\":2}\r\n"
            + "--truckerload_boundary--"
        XCTAssertEqual(body, expected)
        XCTAssertFalse(body.hasSuffix("\r\n"))
        XCTAssertEqual(
            DriveHTTP.createMetadata(fileName: "truckerload_backup_local_dev.tlb"),
            "{\"name\":\"truckerload_backup_local_dev.tlb\",\"parents\":[\"appDataFolder\"]}"
        )
    }

    func testFileSelectionPrefersAStoredId() {
        XCTAssertEqual(DriveHTTP.uploadFileID(stored: " stored ", listed: "listed"), "stored")
        XCTAssertEqual(DriveHTTP.uploadFileID(stored: " ", listed: "listed"), "listed")
        XCTAssertNil(DriveHTTP.uploadFileID(stored: nil, listed: " "))
        XCTAssertEqual(DriveHTTP.downloadFileID(stored: nil, listed: "listed"), "listed")
        XCTAssertNil(DriveHTTP.downloadFileID(stored: "", listed: nil))
    }

    func testRfc3339Millis() {
        XCTAssertEqual(DriveHTTP.parseRfc3339Millis("2024-07-21T12:00:00.000Z"), 1_721_563_200_000)
        XCTAssertEqual(DriveHTTP.parseRfc3339Millis("2024-07-21T12:00:00.500Z"), 1_721_563_200_500)
        XCTAssertEqual(DriveHTTP.parseRfc3339Millis("2024-07-21T12:00:00Z"), 1_721_563_200_000)
        XCTAssertEqual(DriveHTTP.parseRfc3339Millis(nil), 0)
        XCTAssertEqual(DriveHTTP.parseRfc3339Millis("nope"), 0)
    }

    func testUploadCreatesWhenNothingIsStoredAndUpdatesTheStoredId() {
        let created = ScriptedDrive()
        created.responses = [
            DriveHTTPResponse(status: 200, body: #"{"files":[]}"#),
            DriveHTTPResponse(status: 200, body: #"{"id":"created"}"#),
            DriveHTTPResponse(
                status: 200,
                body: #"{"files":[{"id":"created","name":"truckerload_backup_local_dev.tlb","modifiedTime":"2024-07-21T12:00:00Z"}]}"#
            ),
        ]
        let creating = DriveAPI(
            accessToken: "token",
            fileName: "truckerload_backup_local_dev.tlb",
            transport: created
        )
        let uploaded = creating.upload(json: #"{"schemaVersion":2}"#)
        guard case .success(let file) = uploaded else {
            return XCTFail("\(uploaded)")
        }
        XCTAssertEqual(file.id, "created")
        XCTAssertEqual(file.modifiedAt, 1_721_563_200_000)
        XCTAssertEqual(creating.storedFileID, "created")
        XCTAssertEqual(created.sent[1].method, "POST")
        XCTAssertTrue(created.sent[1].url.contains("uploadType=multipart"))
        XCTAssertTrue(created.sent[1].body?.contains("\"parents\":[\"appDataFolder\"]") == true)
        XCTAssertEqual(created.sent[0].headers["Authorization"], "Bearer token")
        XCTAssertNil(created.sent[0].headers["X-Goog-Api-Key"])

        let updated = ScriptedDrive()
        updated.responses = [
            DriveHTTPResponse(
                status: 200,
                body: #"{"files":[{"id":"listed","modifiedTime":"2024-07-21T12:00:00Z"}]}"#
            ),
            DriveHTTPResponse(status: 200, body: ""),
            DriveHTTPResponse(
                status: 200,
                body: #"{"files":[{"id":"stored","modifiedTime":"2024-07-21T12:00:01Z"}]}"#
            ),
        ]
        let api = DriveAPI(
            accessToken: "token",
            fileName: "truckerload_backup_local_dev.tlb",
            storedFileID: "stored",
            transport: updated
        )
        guard case .success(let patched) = api.upload(json: "{}") else {
            return XCTFail("update failed")
        }
        XCTAssertEqual(patched.id, "stored")
        XCTAssertEqual(updated.sent[1].method, "PATCH")
        XCTAssertTrue(updated.sent[1].url.contains("/stored?uploadType=media"))
        XCTAssertFalse(updated.sent[1].url.contains("/listed"))
    }

    func testDownloadUsesListedIdAndReportsAMissingFile() {
        let missing = ScriptedDrive()
        missing.responses = [DriveHTTPResponse(status: 200, body: #"{"files":[]}"#)]
        let api = DriveAPI(accessToken: "token", fileName: "file.tlb", transport: missing)
        guard case .failure(let error) = api.download() else {
            return XCTFail("expected missing file")
        }
        XCTAssertEqual(error.message, "No backup on Google Drive yet")

        let listed = ScriptedDrive()
        listed.responses = [
            DriveHTTPResponse(
                status: 200,
                body: #"{"files":[{"id":"remote","modifiedTime":"2024-07-21T12:00:00.000Z"}]}"#
            ),
            DriveHTTPResponse(status: 200, body: "\u{FEFF}{\"schemaVersion\":2}"),
        ]
        let downloader = DriveAPI(accessToken: "token", fileName: "file.tlb", transport: listed)
        guard case .success(let payload) = downloader.download() else {
            return XCTFail("download failed")
        }
        XCTAssertEqual(payload.file.id, "remote")
        XCTAssertTrue(payload.json.hasPrefix("{"))
        XCTAssertTrue(listed.sent[1].url.contains("/remote?alt=media"))
    }

    func testMetadataFailureIsNotAnEmptyFolderAnd401DoesNotRetry() {
        var sleeps: [Int64] = []
        let failing = ScriptedDrive()
        failing.responses = [
            DriveHTTPResponse(status: 503, body: "unavailable"),
            DriveHTTPResponse(status: 503, body: "unavailable"),
            DriveHTTPResponse(status: 503, body: "unavailable"),
        ]
        let api = DriveAPI(
            accessToken: "token",
            fileName: "file.tlb",
            transport: failing,
            sleep: { sleeps.append($0) }
        )
        guard case .failure(let error) = api.refreshRemote() else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(error.message.contains("List failed (503)"))
        XCTAssertFalse(error.message.contains("No backup"))
        XCTAssertEqual(failing.sent.count, 3)
        XCTAssertEqual(sleeps, [400, 800])

        let denied = ScriptedDrive()
        denied.responses = [DriveHTTPResponse(status: 401, body: "nope")]
        let unauthorized = DriveAPI(accessToken: "token", fileName: "file.tlb", transport: denied)
        guard case .failure(let deniedError) = unauthorized.refreshRemote() else {
            return XCTFail("expected 401")
        }
        XCTAssertTrue(deniedError.message.contains("401"))
        XCTAssertEqual(denied.sent.count, 1)

        let signedOut = DriveAPI(accessToken: " ", fileName: "file.tlb", transport: ScriptedDrive())
        guard case .failure(let signedOutError) = signedOut.refreshRemote() else {
            return XCTFail("expected signed out")
        }
        XCTAssertEqual(signedOutError, .notSignedIn)
    }

    func testInvalidJSONDoesNotRetry() {
        let broken = ScriptedDrive()
        broken.responses = [DriveHTTPResponse(status: 200, body: "not-json")]
        let api = DriveAPI(accessToken: "token", fileName: "file.tlb", transport: broken)
        guard case .failure(let error) = api.refreshRemote() else {
            return XCTFail("expected invalid json")
        }
        XCTAssertEqual(error, .invalidJSON)
        XCTAssertEqual(broken.sent.count, 1)
    }
}

private final class FakeDriveSession: DriveAccountSession {
    var email: String?
    var hasDriveScope = false
    var steps: [DriveParsedSignIn] = []
    var calls: [(requestDriveScope: Bool, hint: String?)] = []

    func signIn(requestDriveScope: Bool, hint: String?) async -> DriveParsedSignIn {
        calls.append((requestDriveScope, hint))
        return steps.removeFirst()
    }

    func signOut() {
        email = nil
        hasDriveScope = false
    }
}

private final class ScriptedDrive: DriveTransport {
    var responses: [DriveHTTPResponse] = []
    var sent: [DriveHTTPRequest] = []

    func send(_ request: DriveHTTPRequest) throws -> DriveHTTPResponse {
        sent.append(request)
        return responses.removeFirst()
    }
}
