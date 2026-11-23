import Foundation
import GRDB

/// Paycheck, diesel, expense, and per-diem rows.
extension AppDatabase {
    static func fetchPaychecks(_ db: Database) throws -> [Paycheck] {
        try Row.fetchAll(db, sql: "SELECT * FROM paycheck ORDER BY date DESC").map(paycheck(from:))
    }


    static func fetchDiesel(_ db: Database) throws -> [Diesel] {
        try Row.fetchAll(db, sql: "SELECT * FROM diesel ORDER BY date DESC").map(diesel(from:))
    }


    static func fetchExpenses(_ db: Database) throws -> [MiscExpense] {
        try Row.fetchAll(db, sql: "SELECT * FROM misc_expense ORDER BY date DESC").map(expense(from:))
    }


    static func fetchPerDiem(_ db: Database) throws -> [PerDiemOverride] {
        try Row.fetchAll(db, sql: "SELECT * FROM per_diem_override ORDER BY isoDate ASC").map(override(from:))
    }


    static func upsert(_ db: Database, _ paycheck: Paycheck) throws {
        try execute(db, """
        INSERT INTO paycheck (
            id, amount, date, company, notes, weekNumber, year, updatedAt,
            grossAmount, driverName, rawText, sourceFileName
        )
        VALUES (\(marks(12)))
        ON CONFLICT(id) DO UPDATE SET
            amount = excluded.amount, date = excluded.date, company = excluded.company,
            notes = excluded.notes, weekNumber = excluded.weekNumber, year = excluded.year,
            updatedAt = excluded.updatedAt, grossAmount = excluded.grossAmount,
            driverName = excluded.driverName, rawText = excluded.rawText,
            sourceFileName = excluded.sourceFileName
        """, [
            paycheck.id.uuidString, paycheck.amount, paycheck.date.timeIntervalSince1970, paycheck.company,
            paycheck.notes, paycheck.weekNumber, paycheck.year, paycheck.updatedAt.timeIntervalSince1970,
            paycheck.grossAmount, paycheck.driverName, paycheck.rawText, paycheck.sourceFileName,
        ])
    }


    static func upsert(_ db: Database, _ fill: Diesel) throws {
        try execute(db, """
        INSERT INTO diesel (
            id, gallons, totalCost, pricePerGallon, location, state, date, odometer, updatedAt,
            discountPricePerGallon, rawText, receiptFileName, sourceFileName
        ) VALUES (\(marks(13)))
        ON CONFLICT(id) DO UPDATE SET
            gallons = excluded.gallons, totalCost = excluded.totalCost, pricePerGallon = excluded.pricePerGallon,
            location = excluded.location, state = excluded.state, date = excluded.date,
            odometer = excluded.odometer, updatedAt = excluded.updatedAt,
            discountPricePerGallon = excluded.discountPricePerGallon, rawText = excluded.rawText,
            receiptFileName = excluded.receiptFileName, sourceFileName = excluded.sourceFileName
        """, [
            fill.id.uuidString, fill.gallons, fill.totalCost, fill.pricePerGallon, fill.location, fill.state,
            fill.date.timeIntervalSince1970, fill.odometer, fill.updatedAt.timeIntervalSince1970,
            fill.discountPricePerGallon, fill.rawText, fill.receiptFileName, fill.sourceFileName,
        ])
    }


    static func upsert(_ db: Database, _ expense: MiscExpense) throws {
        try execute(db, """
        INSERT INTO misc_expense (id, amount, expenseDescription, date, receiptFileName, updatedAt)
        VALUES (\(marks(6)))
        ON CONFLICT(id) DO UPDATE SET
            amount = excluded.amount, expenseDescription = excluded.expenseDescription,
            date = excluded.date, receiptFileName = excluded.receiptFileName, updatedAt = excluded.updatedAt
        """, [
            expense.id.uuidString, expense.amount, expense.expenseDescription,
            expense.date.timeIntervalSince1970, expense.receiptFileName, expense.updatedAt.timeIntervalSince1970,
        ])
    }


    static func paycheck(from row: Row) -> Paycheck {
        Paycheck(
            id: uuid(row, "id") ?? UUID(),
            amount: double(row, "amount") ?? 0,
            date: date(row, "date") ?? Date(timeIntervalSince1970: 0),
            company: string(row, "company"),
            notes: string(row, "notes"),
            weekNumber: int(row, "weekNumber") ?? 0,
            year: int(row, "year") ?? 0,
            grossAmount: double(row, "grossAmount"),
            driverName: string(row, "driverName"),
            rawText: string(row, "rawText"),
            sourceFileName: string(row, "sourceFileName"),
            updatedAt: date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }


    static func diesel(from row: Row) -> Diesel {
        Diesel(
            id: uuid(row, "id") ?? UUID(),
            gallons: double(row, "gallons") ?? 0,
            totalCost: double(row, "totalCost") ?? 0,
            pricePerGallon: double(row, "pricePerGallon") ?? 0,
            location: string(row, "location"),
            state: string(row, "state"),
            date: date(row, "date") ?? Date(timeIntervalSince1970: 0),
            odometer: int(row, "odometer"),
            discountPricePerGallon: double(row, "discountPricePerGallon"),
            rawText: string(row, "rawText"),
            receiptFileName: string(row, "receiptFileName"),
            sourceFileName: string(row, "sourceFileName"),
            updatedAt: date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }


    static func expense(from row: Row) -> MiscExpense {
        MiscExpense(
            id: uuid(row, "id") ?? UUID(),
            amount: double(row, "amount") ?? 0,
            expenseDescription: string(row, "expenseDescription") ?? "",
            date: date(row, "date") ?? Date(timeIntervalSince1970: 0),
            receiptFileName: string(row, "receiptFileName"),
            updatedAt: date(row, "updatedAt") ?? Date(timeIntervalSince1970: 0)
        )
    }


    static func override(from row: Row) -> PerDiemOverride {
        PerDiemOverride(isoDate: string(row, "isoDate") ?? "", included: bool(row, "included"))
    }
}
