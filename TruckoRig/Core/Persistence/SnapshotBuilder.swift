import Foundation
import SwiftData

/// Reads the local database into a backup snapshot.
enum SnapshotBuilder {

    @MainActor
    static func build(from context: ModelContext, now: Date = Date()) throws -> AccountSnapshot {
        AccountSnapshot(
            updatedAt: now,
            loads: try context.fetch(FetchDescriptor<Load>()).map(dto),
            paychecks: try context.fetch(FetchDescriptor<Paycheck>()).map(dto),
            diesel: try context.fetch(FetchDescriptor<Diesel>()).map(dto),
            maintenance: try context.fetch(FetchDescriptor<MaintenanceTask>()).map(dto),
            profile: try context.fetch(FetchDescriptor<DriverProfile>()).first.map(dto)
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
            updatedAt: paycheck.updatedAt
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
            updatedAt: diesel.updatedAt
        )
    }

    static func dto(_ task: MaintenanceTask) -> MaintenanceDTO {
        MaintenanceDTO(
            id: task.id,
            title: task.title,
            dueDate: task.dueDate,
            dueOdometer: task.dueOdometer,
            completedDate: task.completedDate,
            cost: task.cost,
            notes: task.notes,
            isArchived: task.isArchived,
            updatedAt: task.updatedAt
        )
    }

    static func dto(_ profile: DriverProfile) -> ProfileDTO {
        ProfileDTO(
            id: profile.id,
            name: profile.name,
            carrier: profile.carrier,
            truckModel: profile.truckModel,
            truckYear: profile.truckYear,
            licensePlate: profile.licensePlate,
            homeState: profile.homeState,
            weeklyGoal: profile.weeklyGoal,
            updatedAt: profile.updatedAt
        )
    }
}
