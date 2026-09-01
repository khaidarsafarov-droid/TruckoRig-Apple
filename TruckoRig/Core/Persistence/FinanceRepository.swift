import Foundation
import SwiftData

/// Writes for paychecks, fuel and maintenance.
///
/// Same contract as `LoadRepository`: SwiftData first, outbox row in the same save, network later.
@MainActor
struct FinanceRepository {

    let context: ModelContext
    let sync: SyncEngine
    let week: TruckingWeek

    init(context: ModelContext, sync: SyncEngine, week: TruckingWeek = TruckingWeek()) {
        self.context = context
        self.sync = sync
        self.week = week
    }

    // MARK: - Paychecks

    @discardableResult
    func addPaycheck(amount: Double, date: Date, company: String?, notes: String?) throws -> Paycheck {
        let paycheck = Paycheck(amount: amount, date: date, company: company?.nonEmpty, notes: notes?.nonEmpty)
        paycheck.refreshWeek(week: week)
        context.insert(paycheck)
        sync.enqueue(.paycheck, id: paycheck.id, operation: .create, in: context)
        try context.save()
        return paycheck
    }

    func update(_ paycheck: Paycheck, amount: Double, date: Date, company: String?, notes: String?) throws {
        paycheck.amount = amount
        paycheck.date = date
        paycheck.company = company?.nonEmpty
        paycheck.notes = notes?.nonEmpty
        paycheck.updatedAt = Date()
        paycheck.refreshWeek(week: week)
        sync.enqueue(.paycheck, id: paycheck.id, operation: .update, in: context)
        try context.save()
    }

    func delete(_ paycheck: Paycheck) throws {
        let id = paycheck.id
        context.delete(paycheck)
        sync.enqueue(.paycheck, id: id, operation: .delete, in: context)
        try context.save()
    }

    // MARK: - Diesel

    @discardableResult
    func addDiesel(
        gallons: Double,
        totalCost: Double,
        pricePerGallon: Double,
        location: String?,
        state: String?,
        date: Date,
        odometer: Int?
    ) throws -> Diesel {
        let fill = Diesel(
            gallons: gallons,
            totalCost: totalCost,
            pricePerGallon: pricePerGallon,
            location: location?.nonEmpty,
            state: state?.nonEmpty,
            date: date,
            odometer: odometer
        )
        context.insert(fill)
        sync.enqueue(.diesel, id: fill.id, operation: .create, in: context)
        try context.save()
        return fill
    }

    func update(
        _ fill: Diesel,
        gallons: Double,
        totalCost: Double,
        pricePerGallon: Double,
        location: String?,
        state: String?,
        date: Date,
        odometer: Int?
    ) throws {
        fill.gallons = gallons
        fill.totalCost = totalCost
        fill.pricePerGallon = pricePerGallon > 0 ? pricePerGallon : (gallons > 0 ? totalCost / gallons : 0)
        fill.location = location?.nonEmpty
        fill.state = state?.nonEmpty
        fill.date = date
        fill.odometer = odometer
        fill.updatedAt = Date()
        sync.enqueue(.diesel, id: fill.id, operation: .update, in: context)
        try context.save()
    }

    func delete(_ fill: Diesel) throws {
        let id = fill.id
        context.delete(fill)
        sync.enqueue(.diesel, id: id, operation: .delete, in: context)
        try context.save()
    }

    // MARK: - Maintenance

    @discardableResult
    func addTask(
        title: String,
        dueDate: Date?,
        dueOdometer: Int?,
        cost: Double?,
        notes: String?
    ) throws -> MaintenanceTask {
        let task = MaintenanceTask(
            title: title,
            dueDate: dueDate,
            dueOdometer: dueOdometer,
            cost: cost,
            notes: notes?.nonEmpty
        )
        context.insert(task)
        sync.enqueue(.maintenance, id: task.id, operation: .create, in: context)
        try context.save()
        return task
    }

    func update(
        _ task: MaintenanceTask,
        title: String,
        dueDate: Date?,
        dueOdometer: Int?,
        cost: Double?,
        notes: String?
    ) throws {
        task.title = title
        task.dueDate = dueDate
        task.dueOdometer = dueOdometer
        task.cost = cost
        task.notes = notes?.nonEmpty
        task.updatedAt = Date()
        sync.enqueue(.maintenance, id: task.id, operation: .update, in: context)
        try context.save()
    }

    func setCompleted(_ task: MaintenanceTask, completed: Bool) throws {
        task.completedDate = completed ? Date() : nil
        task.updatedAt = Date()
        sync.enqueue(.maintenance, id: task.id, operation: .update, in: context)
        try context.save()
    }

    func setArchived(_ task: MaintenanceTask, archived: Bool) throws {
        task.isArchived = archived
        task.updatedAt = Date()
        sync.enqueue(.maintenance, id: task.id, operation: .update, in: context)
        try context.save()
    }

    func delete(_ task: MaintenanceTask) throws {
        let id = task.id
        context.delete(task)
        sync.enqueue(.maintenance, id: id, operation: .delete, in: context)
        try context.save()
    }
}
