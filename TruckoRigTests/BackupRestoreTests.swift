import XCTest
@testable import TruckoRig

/// Database round trip for the Android v2 JSON journal: ids, money, and orphan-photo pruning.
final class BackupRestoreTests: XCTestCase {

    func testExportImportKeepsAndroidIdsAndPrunesOnlyOrphanPhotos() throws {
        let database = try AppDatabase.ephemeral()
        let defaults = UserDefaults(suiteName: "drive-restore-\(UUID().uuidString)")!
        let settings = AppSettings(scope: .local, defaults: defaults)
        settings.weekStart = .monday
        settings.language = .russian
        settings.weeklyGoal = 4500
        let identity = BackupIdentityStore(defaults: defaults)
        let mediaRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let media = MediaStore(scope: .local, root: mediaRoot)
        defer { try? FileManager.default.removeItem(at: mediaRoot) }

        let kept = Load(
            tripId: "T-KEEP",
            date: Date(timeIntervalSince1970: 1_721_548_800),
            totalRate: 2500,
            totalMiles: 850,
            pointA: "Garner, NC",
            pointB: "Dallas, TX",
            weekNumber: 30,
            year: 2026,
            rawMessage: "Trip ID: T-KEEP",
            parsedAt: Date(timeIntervalSince1970: 1_721_548_800),
            updatedAt: Date(timeIntervalSince1970: 1_721_552_400)
        )
        kept.stops = [
            Stop(type: .pickup, stopNumber: 1, puNumber: "PU-1", city: "Garner", state: "NC", zip: "27529"),
            Stop(type: .delivery, stopNumber: 2, city: "Dallas", state: "TX", zip: "75201"),
        ]
        kept.penalties = [Penalty(summary: "layover", amount: 150, date: kept.date)]
        try database.save(kept)

        let dropped = Load(tripId: "T-DROP", date: kept.date, totalRate: 10, totalMiles: 1)
        try database.save(dropped)

        let keptPhoto = Photo(fileName: "kept.jpg", filePath: "photos/kept.jpg")
        keptPhoto.loadId = kept.id
        let droppedPhoto = Photo(fileName: "dropped.jpg", filePath: "photos/dropped.jpg")
        droppedPhoto.loadId = dropped.id
        let loosePhoto = Photo(fileName: "loose.jpg", filePath: "photos/loose.jpg")
        try database.save(keptPhoto)
        try database.save(droppedPhoto)
        try database.save(loosePhoto)
        try Data("kept".utf8).write(to: media.url(for: "kept.jpg", kind: .photo))
        try Data("dropped".utf8).write(to: media.url(for: "dropped.jpg", kind: .photo))
        try Data("loose".utf8).write(to: media.url(for: "loose.jpg", kind: .photo))

        let paycheck = Paycheck(
            amount: 2800,
            date: kept.date,
            weekNumber: 30,
            year: 2026,
            grossAmount: 3200,
            driverName: "Test Driver",
            rawText: "gross 3200",
            sourceFileName: "pay.pdf"
        )
        paycheck.company = "Carrier"
        try database.save(paycheck)

        let fill = Diesel(
            gallons: 120,
            totalCost: 540.25,
            pricePerGallon: 4.502,
            location: "Pilot, NC",
            state: "NC",
            date: kept.date,
            odometer: 120_000,
            rawText: "diesel 540.25",
            receiptFileName: "receipts/fuel.jpg",
            sourceFileName: "fuel.jpg"
        )
        try database.save(fill)

        let task = MaintenanceTask(
            title: "Oil change",
            startDate: "2026-01-01",
            reminderType: .miles,
            intervalMiles: 15_000,
            odometerAtStart: 120_000,
            createdAt: 1,
            updatedAt: 2
        )
        try database.save(task)
        let archive = MaintenanceArchiveEntry(
            serviceName: "Oil",
            serviceDate: "2025-12-01",
            description: "full synthetic",
            amount: MoneyCents.fromDollars(89),
            photoPath: "receipts/oil.jpg",
            createdAt: 3
        )
        try database.save(archive)

        let exportedAt: Int64 = 1_721_570_000_000
        let first = BackupJournalMapper.export(
            graph: try database.fetchGraph(),
            settings: settings,
            identity: identity,
            accountId: BackupAccount.localDev,
            exportedAt: exportedAt
        )
        XCTAssertEqual(first.loads.count, 2)
        XCTAssertEqual(first.accountId, "local_dev")
        let keptDrive = try XCTUnwrap(first.loads.first { $0.tripId == "T-KEEP" })
        XCTAssertEqual(keptDrive.totalRateCents, 250_000)
        XCTAssertEqual(keptDrive.stopCount, 2)
        XCTAssertEqual(keptDrive.stops.count, 2)
        XCTAssertEqual(first.paychecks[0].netAmountCents, 280_000)
        XCTAssertEqual(first.paychecks[0].grossAmountCents, 320_000)
        XCTAssertEqual(first.diesel[0].totalAmountCents, 54_025)
        XCTAssertEqual(first.diesel[0].pricePerGallonThousandths, 4_502)
        XCTAssertFalse(BackupDataCodec.encode(first).contains("telegram"))
        XCTAssertFalse(BackupDataCodec.encode(first).contains("photos"))

        var remote = first
        remote.loads = [keptDrive]
        let decoded = try BackupDataCodec.decode(BackupDataCodec.encode(remote))
        let plan = BackupJournalMapper.importBackup(decoded, settings: settings, identity: identity)
        let removed = try database.applyBackupJournal(plan)
        for photo in removed.photos {
            media.delete(fileName: photo.fileName, filePath: photo.filePath, kind: .photo)
        }

        let graph = try database.fetchGraph()
        XCTAssertEqual(graph.loads.map(\.tripId), ["T-KEEP"])
        XCTAssertEqual(graph.loads[0].totalRate, 2500, accuracy: 0.001)
        XCTAssertEqual(graph.loads[0].stops?.count, 2)
        XCTAssertEqual(graph.loads[0].penalties?.first?.amount ?? -1, 150, accuracy: 0.001)
        XCTAssertEqual(graph.paychecks.count, 1)
        XCTAssertEqual(graph.paychecks[0].amount, 2800, accuracy: 0.001)
        XCTAssertEqual(graph.paychecks[0].company, "Carrier")
        XCTAssertEqual(graph.diesel.count, 1)
        XCTAssertEqual(graph.diesel[0].state, "NC")
        XCTAssertEqual(graph.diesel[0].odometer, 120_000)
        XCTAssertEqual(graph.diesel[0].receiptFileName, "receipts/fuel.jpg")
        XCTAssertEqual(graph.maintenance.count, 1)
        XCTAssertEqual(graph.maintenanceArchive.count, 1)
        XCTAssertEqual(graph.maintenanceArchive[0].amount.cents, 8_900)
        XCTAssertEqual(graph.maintenanceArchive[0].photoPath, "receipts/oil.jpg")
        let photoNames = Set(graph.photos.map(\.fileName))
        XCTAssertTrue(photoNames.contains("kept.jpg"))
        XCTAssertTrue(photoNames.contains("loose.jpg"))
        XCTAssertFalse(photoNames.contains("dropped.jpg"))
        let loose = try XCTUnwrap(graph.photos.first { $0.fileName == "loose.jpg" })
        XCTAssertNil(loose.loadId)
        let keptRow = try XCTUnwrap(graph.photos.first { $0.fileName == "kept.jpg" })
        XCTAssertEqual(keptRow.loadId, graph.loads[0].id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.url(for: "kept.jpg", kind: .photo).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: media.url(for: "dropped.jpg", kind: .photo).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: media.url(for: "loose.jpg", kind: .photo).path))

        let second = BackupJournalMapper.export(
            graph: try database.fetchGraph(),
            settings: settings,
            identity: identity,
            accountId: BackupAccount.localDev,
            exportedAt: exportedAt
        )
        XCTAssertEqual(second.loads.map(\.id), [keptDrive.id])
        XCTAssertEqual(second.loads[0].stops.map(\.id), keptDrive.stops.map(\.id))
        XCTAssertEqual(second.paychecks.map(\.id), first.paychecks.map(\.id))
        XCTAssertEqual(second.diesel.map(\.id), first.diesel.map(\.id))
        XCTAssertEqual(second.maintenanceTasks.map(\.id), first.maintenanceTasks.map(\.id))
        XCTAssertEqual(second.maintenanceArchive.map(\.id), first.maintenanceArchive.map(\.id))
        XCTAssertEqual(second.appSettings?.languageOrdinal, 0)
        XCTAssertEqual(second.appSettings?.loadWeekStartDay, 2)
        XCTAssertEqual(second.appSettings?.dieselWeekStartDay, 2)
    }

    func testSchemaV1LeavesMaintenanceInPlace() throws {
        let database = try AppDatabase.ephemeral()
        let defaults = UserDefaults(suiteName: "drive-v1-\(UUID().uuidString)")!
        let settings = AppSettings(scope: .local, defaults: defaults)
        let identity = BackupIdentityStore(defaults: defaults)
        let task = MaintenanceTask(title: "Keep", startDate: "2026-01-01", reminderType: .date, createdAt: 1, updatedAt: 1)
        try database.save(task)
        let v1 = #"{"version":1,"accountId":"local_dev","loads":[{"id":"L-1","tripId":"T-1","date":"2026-07-21","totalRate":100}]}"#
        let backup = try BackupDataCodec.decode(v1)
        let plan = BackupJournalMapper.importBackup(backup, settings: settings, identity: identity)
        XCTAssertFalse(plan.replaceMaintenance)
        _ = try database.applyBackupJournal(plan)
        let graph = try database.fetchGraph()
        XCTAssertEqual(graph.loads.map(\.tripId), ["T-1"])
        XCTAssertEqual(graph.maintenance.map(\.title), ["Keep"])
    }

    @MainActor
    func testServiceRoundTripWarnsWhenLocalIsNewerAndAcceptsABom() throws {
        let source = try AppDatabase.ephemeral()
        let defaults = UserDefaults(suiteName: "backup-service-\(UUID().uuidString)")!
        let settings = AppSettings(scope: .local, defaults: defaults)
        let identity = BackupIdentityStore(defaults: defaults)
        let exportedAt: Int64 = 1_700_000_000_000
        let load = Load(
            tripId: "T-FILE",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            totalRate: 100,
            totalMiles: 10,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try source.save(load)
        let file = try BackupService.exportFile(
            from: source,
            settings: settings,
            identity: identity,
            exportedAt: exportedAt
        )
        XCTAssertTrue(file.fileName.hasPrefix("TruckoRig_Backup_"))
        XCTAssertTrue(file.fileName.hasSuffix(".json"))
        XCTAssertEqual(file.loadCount, 1)
        XCTAssertTrue(
            try BackupService.shouldWarnBeforeRestore(in: source, backupExportedAt: exportedAt)
        )
        XCTAssertFalse(
            BackupService.shouldWarnBeforeRestore(localNewestMillis: exportedAt, backupExportedAt: exportedAt)
        )

        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(file.data)
        let preview = try BackupService.preview(data: bom)
        XCTAssertFalse(preview.unbound)
        XCTAssertEqual(preview.exportedAt, exportedAt)

        let destination = try AppDatabase.ephemeral()
        let mediaRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: mediaRoot) }
        let restored = try BackupService.restoreBackupJSON(
            preview.json,
            into: destination,
            settings: settings,
            identity: BackupIdentityStore(defaults: defaults),
            media: MediaStore(scope: .local, root: mediaRoot),
            allowUnboundAccount: false
        )
        XCTAssertEqual(restored.loads, 1)
        XCTAssertEqual(try destination.fetchGraph().loads.map(\.tripId), ["T-FILE"])

        let newer = Data(#"{"schemaVersion":99,"loads":[]}"#.utf8)
        XCTAssertThrowsError(try BackupService.preview(data: newer)) { error in
            XCTAssertEqual(error as? BackupService.Failure, .schemaTooNew(99))
        }
    }
}
