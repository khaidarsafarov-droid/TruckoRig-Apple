import Foundation

/// Merges a backup snapshot into the local database.
///
/// Conflicts resolve last-write-wins on `updatedAt`. A row the file has but this device does not
/// is inserted; a row this device edited more recently is kept, so a restore never overwrites
/// work recorded after the backup.
enum SnapshotApplier {

    struct Report: Equatable {
        var inserted = 0
        var updated = 0
        var skipped = 0
        var deleted = 0
    }

    @MainActor
    @discardableResult
    static func apply(
        _ snapshot: AccountSnapshot,
        to database: AppDatabase,
        week: TruckingWeek = TruckingWeek(),
        onRemovedMedia: ((AppDatabase.RemovedMedia) -> Void)? = nil
    ) throws -> Report {
        var report = Report()
        let graph = try database.fetchGraph()

        let localLoads = Dictionary(
            graph.loads.map { ($0.tripId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for remote in snapshot.loads {
            let key = TripID.normalize(remote.tripId)
            guard let local = localLoads[key] else {
                guard !remote.isDeleted else { continue }
                try database.save(makeLoad(remote, week: week))
                report.inserted += 1
                continue
            }
            if remote.isDeleted {
                let removed = try database.delete(local)
                onRemovedMedia?(removed)
                report.deleted += 1
                continue
            }
            guard remote.updatedAt > local.updatedAt else {
                report.skipped += 1
                continue
            }
            update(local, with: remote, week: week)
            try database.save(local)
            report.updated += 1
        }

        try mergeSimple(
            remote: snapshot.paychecks,
            local: graph.paychecks,
            id: \.id,
            localId: \.id,
            remoteUpdatedAt: \.updatedAt,
            localUpdatedAt: \.updatedAt,
            isDeleted: \.isDeleted,
            report: &report,
            insert: { try database.save($0) },
            delete: { try database.delete($0) },
            make: { dto in
                Paycheck(
                    id: dto.id,
                    amount: dto.amount,
                    date: dto.date,
                    company: dto.company,
                    notes: dto.notes,
                    weekNumber: dto.weekNumber,
                    year: dto.year,
                    updatedAt: dto.updatedAt
                )
            },
            update: { local, dto in
                local.amount = dto.amount
                local.date = dto.date
                local.company = dto.company
                local.notes = dto.notes
                local.weekNumber = dto.weekNumber
                local.year = dto.year
                local.updatedAt = dto.updatedAt
                try database.save(local)
            }
        )

        try mergeSimple(
            remote: snapshot.diesel,
            local: graph.diesel,
            id: \.id,
            localId: \.id,
            remoteUpdatedAt: \.updatedAt,
            localUpdatedAt: \.updatedAt,
            isDeleted: \.isDeleted,
            report: &report,
            insert: { try database.save($0) },
            delete: { try database.delete($0) },
            make: { dto in
                Diesel(
                    id: dto.id,
                    gallons: dto.gallons,
                    totalCost: dto.totalCost,
                    pricePerGallon: dto.pricePerGallon,
                    location: dto.location,
                    state: dto.state,
                    date: dto.date,
                    odometer: dto.odometer,
                    updatedAt: dto.updatedAt
                )
            },
            update: { local, dto in
                local.gallons = dto.gallons
                local.totalCost = dto.totalCost
                local.pricePerGallon = dto.pricePerGallon
                local.location = dto.location
                local.state = dto.state
                local.date = dto.date
                local.odometer = dto.odometer
                local.updatedAt = dto.updatedAt
                try database.save(local)
            }
        )

        try mergeSimple(
            remote: snapshot.maintenance,
            local: graph.maintenance,
            id: \.id,
            localId: \.id,
            remoteUpdatedAt: \.updatedAt,
            localUpdatedAt: \.updatedAt,
            isDeleted: \.isDeleted,
            report: &report,
            insert: { try database.save($0) },
            delete: { try database.delete($0) },
            make: { dto in
                MaintenanceTask(
                    id: dto.id,
                    title: dto.title,
                    dueDate: dto.dueDate,
                    dueOdometer: dto.dueOdometer,
                    completedDate: dto.completedDate,
                    cost: dto.cost,
                    notes: dto.notes,
                    isArchived: dto.isArchived,
                    updatedAt: dto.updatedAt
                )
            },
            update: { local, dto in
                local.title = dto.title
                local.dueDate = dto.dueDate
                local.dueOdometer = dto.dueOdometer
                local.completedDate = dto.completedDate
                local.cost = dto.cost
                local.notes = dto.notes
                local.isArchived = dto.isArchived
                local.updatedAt = dto.updatedAt
                try database.save(local)
            }
        )

        if let remoteProfile = snapshot.profile {
            if let local = graph.profile, remoteProfile.updatedAt > local.updatedAt {
                local.name = remoteProfile.name
                local.carrier = remoteProfile.carrier
                local.truckModel = remoteProfile.truckModel
                local.truckYear = remoteProfile.truckYear
                local.licensePlate = remoteProfile.licensePlate
                local.homeState = remoteProfile.homeState
                local.weeklyGoal = remoteProfile.weeklyGoal
                local.updatedAt = remoteProfile.updatedAt
                try database.save(local)
                report.updated += 1
            } else if graph.profile == nil {
                try database.save(DriverProfile(
                    id: remoteProfile.id,
                    name: remoteProfile.name,
                    carrier: remoteProfile.carrier,
                    truckModel: remoteProfile.truckModel,
                    truckYear: remoteProfile.truckYear,
                    licensePlate: remoteProfile.licensePlate,
                    homeState: remoteProfile.homeState,
                    weeklyGoal: remoteProfile.weeklyGoal,
                    updatedAt: remoteProfile.updatedAt
                ))
                report.inserted += 1
            }
        }

        return report
    }

    // MARK: - Loads

    private static func makeLoad(_ dto: LoadDTO, week: TruckingWeek) -> Load {
        let load = Load(
            id: dto.id,
            tripId: dto.tripId,
            date: dto.date,
            totalRate: dto.totalRate,
            totalMiles: dto.totalMiles,
            pointA: dto.pointA,
            pointB: dto.pointB,
            puCount: dto.puCount,
            delCount: dto.delCount,
            stopCount: dto.stopCount,
            weekNumber: dto.weekNumber,
            year: dto.year,
            parsedAt: dto.parsedAt,
            updatedAt: dto.updatedAt,
            isDispute: dto.isDispute,
            disputeCompleted: dto.disputeCompleted,
            disputeResponseDate: dto.disputeResponseDate,
            disputeAmount: dto.disputeAmount,
            actualFinishDate: dto.actualFinishDate,
            firstPickupAt: dto.firstPickupAt,
            lastDeliveryAt: dto.lastDeliveryAt,
            durationDays: dto.durationDays
        )
        load.stops = dto.stops.map(makeStop)
        load.penalties = dto.penalties.map(makePenalty)
        load.refreshDerivedFields(week: week)
        return load
    }

    private static func makeStop(_ dto: StopDTO) -> Stop {
        Stop(
            id: dto.id,
            type: StopType(rawValue: dto.type) ?? .pickup,
            stopNumber: dto.stopNumber,
            puNumber: dto.puNumber,
            note: dto.note,
            facility: dto.facility,
            fullAddress: dto.fullAddress,
            city: dto.city,
            state: dto.state,
            zip: dto.zip,
            scheduledTime: dto.scheduledTime,
            scheduledTimeRaw: dto.scheduledTimeRaw,
            timezone: dto.timezone
        )
    }

    private static func makePenalty(_ dto: PenaltyDTO) -> Penalty {
        Penalty(id: dto.id, summary: dto.summary, amount: dto.amount, date: dto.date)
    }

    private static func update(_ load: Load, with dto: LoadDTO, week: TruckingWeek) {
        load.date = dto.date
        load.totalRate = dto.totalRate
        load.totalMiles = dto.totalMiles
        load.pointA = dto.pointA
        load.pointB = dto.pointB
        load.isDispute = dto.isDispute
        load.disputeCompleted = dto.disputeCompleted
        load.disputeResponseDate = dto.disputeResponseDate
        load.disputeAmount = dto.disputeAmount
        load.actualFinishDate = dto.actualFinishDate
        load.updatedAt = dto.updatedAt
        // parsedAt is immutable: it records when the trip first entered the journal.

        load.stops = dto.stops.map(makeStop)
        load.penalties = dto.penalties.map(makePenalty)
        load.refreshDerivedFields(week: week)
    }

    // MARK: - Generic merge

    private static func mergeSimple<DTO, Model>(
        remote: [DTO],
        local: [Model],
        id: KeyPath<DTO, UUID>,
        localId: KeyPath<Model, UUID>,
        remoteUpdatedAt: KeyPath<DTO, Date>,
        localUpdatedAt: KeyPath<Model, Date>,
        isDeleted: KeyPath<DTO, Bool>,
        report: inout Report,
        insert: (Model) throws -> Void,
        delete: (Model) throws -> Void,
        make: (DTO) -> Model,
        update: (Model, DTO) throws -> Void
    ) throws {
        let index = Dictionary(local.map { ($0[keyPath: localId], $0) }, uniquingKeysWith: { first, _ in first })
        for dto in remote {
            guard let existing = index[dto[keyPath: id]] else {
                guard !dto[keyPath: isDeleted] else { continue }
                try insert(make(dto))
                report.inserted += 1
                continue
            }
            if dto[keyPath: isDeleted] {
                try delete(existing)
                report.deleted += 1
                continue
            }
            guard dto[keyPath: remoteUpdatedAt] > existing[keyPath: localUpdatedAt] else {
                report.skipped += 1
                continue
            }
            try update(existing, dto)
            report.updated += 1
        }
    }
}
