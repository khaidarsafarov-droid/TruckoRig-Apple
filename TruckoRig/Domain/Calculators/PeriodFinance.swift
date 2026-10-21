import Foundation

/// One settlement. Extra rows for the same reporting week are ignored; the latest write wins.
public struct PaycheckSlice: Equatable, Sendable {
    public var amount: Double
    public var weekNumber: Int
    public var year: Int
    public var date: Date
    public var updatedAt: Date

    public init(amount: Double, weekNumber: Int, year: Int, date: Date, updatedAt: Date) {
        self.amount = amount
        self.weekNumber = weekNumber
        self.year = year
        self.date = date
        self.updatedAt = updatedAt
    }
}

/// One fill-up. `discountPricePerGallon` is optional because older journals did not store it.
public struct DieselSlice: Equatable, Sendable {
    public var gallons: Double
    public var totalCost: Double
    public var pricePerGallon: Double
    public var discountPricePerGallon: Double?
    public var date: Date

    public init(
        gallons: Double,
        totalCost: Double,
        pricePerGallon: Double,
        discountPricePerGallon: Double? = nil,
        date: Date
    ) {
        self.gallons = gallons
        self.totalCost = totalCost
        self.pricePerGallon = pricePerGallon
        self.discountPricePerGallon = discountPricePerGallon
        self.date = date
    }
}

/// Paycheck in and diesel out, kept separate. The report does not subtract them.
public struct PeriodFinance: Equatable, Sendable {
    public var paycheckTotal: Double
    public var dieselTotal: Double
    public var dieselGallons: Double
    public var dieselSavings: Double

    public init(
        paycheckTotal: Double = 0,
        dieselTotal: Double = 0,
        dieselGallons: Double = 0,
        dieselSavings: Double = 0
    ) {
        self.paycheckTotal = paycheckTotal
        self.dieselTotal = dieselTotal
        self.dieselGallons = dieselGallons
        self.dieselSavings = dieselSavings
    }

    public var avgPricePerGallon: Double? {
        dieselGallons > 0 ? dieselTotal / dieselGallons : nil
    }

    public var hasData: Bool { paycheckTotal > 0 || dieselTotal > 0 }
}

public enum PeriodFinanceCalculator {

    /// `range` is half-open `[start, end)`. `nil` counts every row.
    public static func calculate(
        paychecks: [PaycheckSlice],
        diesel: [DieselSlice],
        range: Range<Date>? = nil
    ) -> PeriodFinance {
        let checks = paychecks.filter { contains($0.date, range) }
        let fills = diesel.filter { contains($0.date, range) }

        let paycheckTotal = Dictionary(grouping: checks) { WeekRef(weekNumber: $0.weekNumber, year: $0.year) }
            .values
            .reduce(0.0) { total, rows in
                total + (rows.max { $0.updatedAt < $1.updatedAt }?.amount ?? 0)
            }

        let dieselTotal = fills.reduce(0.0) { $0 + $1.totalCost }
        let gallons = fills.reduce(0.0) { $0 + $1.gallons }
        let dieselSavings = fills.reduce(0.0) { $0 + Self.savings(of: $1) }

        return PeriodFinance(
            paycheckTotal: GoalMoneyMath.roundMoney(paycheckTotal),
            dieselTotal: GoalMoneyMath.roundMoney(dieselTotal),
            dieselGallons: gallons,
            dieselSavings: GoalMoneyMath.roundMoney(dieselSavings)
        )
    }

    /// `(list − discount) × gallons` when both prices are positive and the discount is lower.
    public static func savings(of fill: DieselSlice) -> Double {
        guard fill.gallons > 0,
              fill.pricePerGallon > 0,
              let discount = fill.discountPricePerGallon,
              discount > 0
        else { return 0 }
        let gap = fill.pricePerGallon - discount
        guard gap > 0 else { return 0 }
        return gap * fill.gallons
    }

    private static func contains(_ date: Date, _ range: Range<Date>?) -> Bool {
        guard let range else { return true }
        return range.contains(date)
    }
}
