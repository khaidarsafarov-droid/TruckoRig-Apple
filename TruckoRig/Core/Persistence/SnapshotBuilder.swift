import Foundation

/// Reads the local database into a backup snapshot.
enum SnapshotBuilder {

    @MainActor
    static func build(from database: AppDatabase, now: Date = Date()) throws -> AccountSnapshot {
        let graph = try database.fetchGraph()
        return AccountSnapshot(
            schemaVersion: 2,
            updatedAt: now,
            loads: graph.loads.map(dto),
            paychecks: graph.paychecks.map(dto),
            diesel: graph.diesel.map(dto),
            maintenance: graph.maintenance.map(dto),
            profile: graph.profile.map(dto),
            maintenanceArchive: graph.maintenanceArchive.map(dto),
            expenses: graph.expenses.map(dto),
            perDiemOverrides: graph.perDiemOverrides.map { PerDiemOverrideDTO(isoDate: $0.isoDate, included: $0.included) }
        )
    }

    static func dto(_ load: Load) -> LoadDTO {
        LoadDTO(
            id: load.id,
            tripId: load.tripId,
            date: load.date,
            totalRate: load.totalRate,
            totalMiles: load.totalMiles,
            pointA: load.pointA,
            pointB: load.pointB,
            puCount: load.puCount,
            delCount: load.delCount,
            stopCount: load.stopCount,
            weekNumber: load.weekNumber,
            year: load.year,
            parsedAt: load.parsedAt,
            updatedAt: load.updatedAt,
            isDispute: load.isDispute,
            disputeCompleted: load.disputeCompleted,
            disputeResponseDate: load.disputeResponseDate,
            disputeAmount: load.disputeAmount,
            actualFinishDate: load.actualFinishDate,
            firstPickupAt: load.firstPickupAt,
            lastDeliveryAt: load.lastDeliveryAt,
            durationDays: load.durationDays,
            stops: load.sortedStops.map(dto),
            penalties: (load.penalties ?? []).map(dto)
        )
    }

    static func dto(_ stop: Stop) -> StopDTO {
        StopDTO(
            id: stop.id,
            type: stop.type.rawValue,
            stopNumber: stop.stopNumber,
            puNumber: stop.puNumber,
            note: stop.note,
            facility: stop.facility,
            fullAddress: stop.fullAddress,
            city: stop.city,
            state: stop.state,
            zip: stop.zip,
            scheduledTime: stop.scheduledTime,
            scheduledTimeRaw: stop.scheduledTimeRaw,
            timezone: stop.timezone
        )
    }

    static func dto(_ penalty: Penalty) -> PenaltyDTO {
        PenaltyDTO(id: penalty.id, summary: penalty.summary, amount: penalty.amount, date: penalty.date)
    }

    static func dto(_ paycheck: Paycheck) -> PaycheckDTO {
        PaycheckDTO(
            id: paycheck.id,
            amount: paycheck.amount,
            date: paycheck.date,
            company: paycheck.company,
            notes: paycheck.notes,
            weekNumber: paycheck.weekNumber,
            year: paycheck.year,
            updatedAt: paycheck.updatedAt,
            grossAmount: paycheck.grossAmount,
            driverName: paycheck.driverName,
            rawText: paycheck.rawText,
            sourceFileName: paycheck.sourceFileName
        )
    }

    static func dto(_ diesel: Diesel) -> DieselDTO {
        DieselDTO(
            id: diesel.id,
            gallons: diesel.gallons,
            totalCost: diesel.totalCost,
            pricePerGallon: diesel.pricePerGallon,
            location: diesel.location,
            state: diesel.state,
            date: diesel.date,
            odometer: diesel.odometer,
            updatedAt: diesel.updatedAt,
            discountPricePerGallon: diesel.discountPricePerGallon,
            rawText: diesel.rawText,
            receiptFileName: diesel.receiptFileName,
            sourceFileName: diesel.sourceFileName
        )
    }

    static func dto(_ task: MaintenanceTask) -> MaintenanceDTO {
        MaintenanceDTO(task: task)
    }

    static func dto(_ entry: MaintenanceArchiveEntry) -> MaintenanceArchiveDTO {
        MaintenanceArchiveDTO(entry: entry)
    }

    static func dto(_ profile: DriverProfile) -> ProfileDTO {
        ProfileDTO(
            id: profile.id,
            name: profile.name,
            truckModel: profile.truckModel,
            truckYear: profile.truckYear,
            licensePlate: profile.licensePlate,
            homeState: profile.homeState,
            weeklyGoal: profile.weeklyGoal,
            updatedAt: profile.updatedAt
        )
    }

    static func dto(_ expense: MiscExpense) -> MiscExpenseDTO {
        MiscExpenseDTO(
            id: expense.id,
            amount: expense.amount,
            expenseDescription: expense.expenseDescription,
            date: expense.date,
            receiptFileName: expense.receiptFileName,
            updatedAt: expense.updatedAt
        )
    }
}
