import Foundation

/// Manual per-diem calendar edits on top of load-derived on-duty days.
public struct PerDiemOverrideSnapshot: Equatable, Sendable {
    public var included: Set<String>
    public var excluded: Set<String>

    public init(included: Set<String> = [], excluded: Set<String> = []) {
        self.included = included
        self.excluded = excluded
    }
}

public enum PerDiemOverrideMutation: Equatable, Sendable {
    case upsertIncluded
    case upsertExcluded
    case delete
}

public enum PerDiemDayOverrides {
    public static func apply(autoDates: Set<String>, snapshot: PerDiemOverrideSnapshot) -> Set<String> {
        autoDates.subtracting(snapshot.excluded).union(snapshot.included)
    }

    public static func mutationForToggle(
        isoDate: String,
        autoDates: Set<String>,
        effectiveDates: Set<String>
    ) -> PerDiemOverrideMutation {
        let on = effectiveDates.contains(isoDate)
        let auto = autoDates.contains(isoDate)
        switch (on, auto) {
        case (true, true): return .upsertExcluded
        case (true, false): return .delete
        case (false, true): return .delete
        case (false, false): return .upsertIncluded
        }
    }
}

/// IRS-style trucker per-diem estimate. Days are the same on-road windows as the weekly goal.
public enum PerDiemCalculator {
    public static let dailyRate = 69.0

    public static func uniqueOnDutyDates(
        loads: [LoadSummary],
        year: Int,
        today: Date,
        calendar: Calendar
    ) -> Set<String> {
        let prefix = String(format: "%04d-", year)
        return LoadYieldCalculator.coveredISODates(loads: loads, through: today, calendar: calendar)
            .filter { $0.hasPrefix(prefix) }
    }

    public static func dayCount(loads: [LoadSummary], year: Int, today: Date, calendar: Calendar) -> Int {
        uniqueOnDutyDates(loads: loads, year: year, today: today, calendar: calendar).count
    }

    public static func amount(dayCount: Int) -> Double {
        Double(dayCount) * dailyRate
    }
}

/// What the driver can include in the accountant export.
public enum AccountantExportSection: String, CaseIterable, Sendable {
    case loads
    case diesel
    case perDiem
    case maintenance
    case all

    public static func resolve(_ sections: Set<AccountantExportSection>) -> Set<AccountantExportSection> {
        if sections.contains(.all) || sections.isEmpty {
            return [.loads, .diesel, .perDiem, .maintenance]
        }
        return sections.subtracting([.all])
    }
}

/// Quarterly estimate from paycheck gross, diesel and per diem. A guide, not tax advice.
public struct TaxEstimate: Equatable, Sendable {
    public var grossIncome: Double
    public var dieselDeductions: Double
    public var perDiemDays: Int
    public var perDiemAmount: Double
    public var taxableIncome: Double
    public var selfEmploymentTax: Double
    public var federalTax: Double
    public var totalOwed: Double
    public var daysUntilNextQuarter: Int
    public var nextQuarterLabel: String

    public static func make(
        grossIncome: Double,
        dieselDeductions: Double,
        perDiemDays: Int,
        today: Date,
        calendar: Calendar
    ) -> TaxEstimate {
        let perDiemAmount = PerDiemCalculator.amount(dayCount: perDiemDays)
        let taxable = max(0, grossIncome - dieselDeductions - perDiemAmount)
        let selfEmployment = taxable * 0.153 * 0.9235
        let federal = federalTax(taxable)
        let quarter = nextQuarter(today: today, calendar: calendar)
        return TaxEstimate(
            grossIncome: grossIncome,
            dieselDeductions: dieselDeductions,
            perDiemDays: perDiemDays,
            perDiemAmount: perDiemAmount,
            taxableIncome: taxable,
            selfEmploymentTax: selfEmployment,
            federalTax: federal,
            totalOwed: selfEmployment + federal,
            daysUntilNextQuarter: quarter.days,
            nextQuarterLabel: quarter.label
        )
    }

    /// 2024 single-filer brackets, same table as the Android tax screen.
    public static func federalTax(_ taxable: Double) -> Double {
        guard taxable > 0 else { return 0 }
        let brackets: [(Double, Double)] = [
            (11_600, 0.10),
            (47_150, 0.12),
            (100_525, 0.22),
            (191_950, 0.24),
            (243_725, 0.32),
            (609_350, 0.35),
            (Double.greatestFiniteMagnitude, 0.37),
        ]
        var tax = 0.0
        var remaining = taxable
        var previous = 0.0
        for (limit, rate) in brackets {
            let size = max(0, limit - previous)
            let inBracket = min(remaining, size)
            tax += inBracket * rate
            remaining -= inBracket
            if remaining <= 0 { break }
            previous = limit
        }
        return tax
    }

    /// Next estimated-tax date: Apr 15, Jun 15, Sep 15, then Jan 15 of the following year.
    public static func nextQuarter(today: Date, calendar: Calendar) -> (days: Int, label: String) {
        let year = calendar.component(.year, from: today)
        let dates: [(Int, Int, String)] = [(4, 15, "Q1"), (6, 15, "Q2"), (9, 15, "Q3"), (1, 15, "Q4")]
        for (month, day, label) in dates {
            var components = DateComponents()
            components.year = month == 1 ? year + 1 : year
            components.month = month
            components.day = day
            components.hour = 0
            components.minute = 0
            components.second = 0
            guard let due = calendar.date(from: components) else { continue }
            let millis = due.timeIntervalSince(today) * 1000
            let days = Int((millis + 23 * 60 * 60 * 1000) / (24 * 60 * 60 * 1000))
            if days > 0 {
                return (days, "\(label) \(month)/\(day)")
            }
        }
        return (0, "")
    }
}

public enum AccountantExport {
    public struct Row: Equatable, Sendable {
        public var section: String
        public var cells: [String]
        public init(section: String, cells: [String]) {
            self.section = section
            self.cells = cells
        }
    }

    public static func csv(year: Int, rows: [Row]) -> String {
        var lines = ["section,year,c1,c2,c3,c4"]
        for row in rows {
            let padded = row.cells + Array(repeating: "", count: max(0, 4 - row.cells.count))
            let cells = ([row.section, String(year)] + padded.prefix(4)).map(MiscExpenseFields.csvQuote)
            lines.append(cells.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func isEmpty(sections: Set<AccountantExportSection>, counts: [AccountantExportSection: Int]) -> Bool {
        let resolved = AccountantExportSection.resolve(sections)
        return resolved.allSatisfy { (counts[$0] ?? 0) == 0 }
    }
}
