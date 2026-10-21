import Foundation

/// Writes for paychecks, fuel and maintenance.
@MainActor
struct FinanceRepository {

    let database: AppDatabase
    let week: TruckingWeek
    let onDidSave: (() -> Void)?

    init(database: AppDatabase, week: TruckingWeek = TruckingWeek(), onDidSave: (() -> Void)? = nil) {
        self.database = database
        self.week = week
        self.onDidSave = onDidSave
    }

    private func saved() {
        onDidSave?()
    }

    // MARK: - Paychecks

    @discardableResult
    func addPaycheck(amount: Double, date: Date, company: String?, notes: String?) throws -> Paycheck {
        let paycheck = Paycheck(amount: amount, date: date, company: company?.nonEmpty, notes: notes?.nonEmpty)
        paycheck.refreshWeek(week: week)
        try database.save(paycheck)
        saved()
        return paycheck
    }

    func update(_ paycheck: Paycheck, amount: Double, date: Date, company: String?, notes: String?) throws {
        paycheck.amount = amount
        paycheck.date = date
        paycheck.company = company?.nonEmpty
        paycheck.notes = notes?.nonEmpty
        paycheck.updatedAt = Date()
        paycheck.refreshWeek(week: week)
        try database.save(paycheck)
        saved()
    }

    func delete(_ paycheck: Paycheck) throws {
        try database.delete(paycheck)
        saved()
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
        try database.save(fill)
        saved()
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
        try database.save(fill)
        saved()
    }

    func delete(_ fill: Diesel) throws {
        try database.delete(fill)
        saved()
    }

    // MARK: - Maintenance

    func addTask(_ task: MaintenanceTask) throws {
        try database.save(task)
        saved()
    }

    func complete(_ task: MaintenanceTask, now: Date = Date()) throws {
        var copy = task
        let millis = Int64(now.timeIntervalSince1970 * 1000)
        copy.isCompleted = true
        copy.completedAt = millis
        copy.updatedAt = millis
        try database.save(copy)
        saved()
    }

    func delete(_ task: MaintenanceTask) throws {
        try database.delete(task)
        saved()
    }

    func addArchive(_ entries: [MaintenanceArchiveEntry]) throws {
        guard !entries.isEmpty else { return }
        for entry in entries {
            try database.save(entry)
        }
        saved()
    }

    func deleteVisit(ids: [String], store: MediaStore) throws {
        let paths = try database.deleteArchives(ids: ids)
        for path in paths {
            store.deleteReceipt(relativePath: path)
        }
        saved()
    }
}
