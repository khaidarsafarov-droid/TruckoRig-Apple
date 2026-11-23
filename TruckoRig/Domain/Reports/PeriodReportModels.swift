import Foundation

/// Week or month a driver can hand to a dispatcher.
///
/// A week is the trucking reporting week already stored on each load (the same week the home
/// card totals). A month is the calendar month, and a load counts when its pickup-to-finish
/// span overlaps that month, matching the journal's "this month" filter.
public enum PeriodReportScope: Equatable, Sendable {
    case week(WeekRef)
    case month(year: Int, month: Int)
}

/// Which period the share sheet is asking for. The day inside it selects the week or the month.
public enum PeriodReportKind: Equatable, Hashable, Sendable {
    case week
    case month
}

/// Home-screen period the share button reads. Anything that is not a week or a month is `.other`.
public enum PeriodReportHomePeriod: Equatable, Sendable {
    case thisWeek
    case lastWeek
    case chosenWeek
    case thisMonth
    case other
}

/// Language of the shared report. Follows the app language; an unknown code stays English.
public enum PeriodReportLanguage: Equatable, Sendable {
    case english
    case russian
    case french
    case spanish

    public static func from(code: String) -> PeriodReportLanguage {
        let lower = code.lowercased()
        if lower.hasPrefix("ru") { return .russian }
        if lower.hasPrefix("fr") { return .french }
        if lower.hasPrefix("es") { return .spanish }
        return .english
    }

    public var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .russian: return Locale(identifier: "ru_RU")
        case .french: return Locale(identifier: "fr_FR")
        case .spanish: return Locale(identifier: "es_ES")
        }
    }
}

/// One deduction on a load. The summary is the driver's own note ("Late fee").
public struct PeriodReportPenalty: Equatable, Sendable {
    public var summary: String
    public var amount: Double

    public init(summary: String, amount: Double) {
        self.summary = summary
        self.amount = amount
    }
}

/// Fields the journal actually stores for one load. There is no broker or customer name.
public struct PeriodReportLoadInput: Equatable, Sendable {
    public var tripId: String
    public var rate: Double
    public var loadedMiles: Double
    public var emptyMiles: Double
    public var filedOn: Date
    public var pickupAt: Date?
    public var deliveryAt: Date?
    public var finishAt: Date?
    public var weekNumber: Int
    public var year: Int
    public var origin: String
    public var destination: String
    public var equipmentCode: String?
    public var source: LoadSourceTag
    public var isDispute: Bool
    public var disputeCompleted: Bool
    public var notes: [String]
    public var penalties: [PeriodReportPenalty]

    public init(
        tripId: String,
        rate: Double,
        loadedMiles: Double,
        emptyMiles: Double,
        filedOn: Date,
        pickupAt: Date? = nil,
        deliveryAt: Date? = nil,
        finishAt: Date? = nil,
        weekNumber: Int,
        year: Int,
        origin: String = "",
        destination: String = "",
        equipmentCode: String? = nil,
        source: LoadSourceTag = .manual,
        isDispute: Bool = false,
        disputeCompleted: Bool = false,
        notes: [String] = [],
        penalties: [PeriodReportPenalty] = []
    ) {
        self.tripId = tripId
        self.rate = rate
        self.loadedMiles = loadedMiles
        self.emptyMiles = emptyMiles
        self.filedOn = filedOn
        self.pickupAt = pickupAt
        self.deliveryAt = deliveryAt
        self.finishAt = finishAt
        self.weekNumber = weekNumber
        self.year = year
        self.origin = origin
        self.destination = destination
        self.equipmentCode = equipmentCode
        self.source = source
        self.isDispute = isDispute
        self.disputeCompleted = disputeCompleted
        self.notes = notes
        self.penalties = penalties
    }

    var drivenMiles: Double { loadedMiles + max(0, emptyMiles) }

    var sortDate: Date { pickupAt ?? filedOn }
}

/// One fill-up. Gallons stay in US gallons; the report converts them for display.
public struct PeriodReportFuelFill: Equatable, Sendable {
    public var totalCost: Double
    public var gallons: Double
    public var date: Date

    public init(totalCost: Double, gallons: Double, date: Date) {
        self.totalCost = totalCost
        self.gallons = gallons
        self.date = date
    }
}

/// A non-fuel expense (parking, scales, a wash).
public struct PeriodReportExpense: Equatable, Sendable {
    public var amount: Double
    public var date: Date

    public init(amount: Double, date: Date) {
        self.amount = amount
        self.date = date
    }
}

/// Everything the builder needs. The caller passes the whole journal; the builder keeps the period.
public struct PeriodReportRequest: Sendable {
    public var driverName: String
    public var scope: PeriodReportScope
    public var loads: [PeriodReportLoadInput]
    public var fuel: [PeriodReportFuelFill]
    public var expenses: [PeriodReportExpense]
    public var weeklyGoal: Double
    public var generatedAt: Date
    public var language: PeriodReportLanguage
    public var measurementSystem: MeasurementSystem
    public var week: TruckingWeek

    public init(
        driverName: String,
        scope: PeriodReportScope,
        loads: [PeriodReportLoadInput],
        fuel: [PeriodReportFuelFill],
        expenses: [PeriodReportExpense],
        weeklyGoal: Double,
        generatedAt: Date,
        language: PeriodReportLanguage,
        measurementSystem: MeasurementSystem,
        week: TruckingWeek
    ) {
        self.driverName = driverName
        self.scope = scope
        self.loads = loads
        self.fuel = fuel
        self.expenses = expenses
        self.weeklyGoal = weeklyGoal
        self.generatedAt = generatedAt
        self.language = language
        self.measurementSystem = measurementSystem
        self.week = week
    }
}

/// One labeled fact. Text prints `label: value`. The PDF puts the pair in a table row.
public struct PeriodReportLine: Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Dollar and mile totals for the period, before display formatting.
public struct PeriodReportTotals: Equatable, Sendable {
    public var gross: Double
    public var loadCount: Int
    public var loadedMiles: Double
    public var emptyMiles: Double
    public var drivenMiles: Double
    /// Dollars per stored mile. Zero when the period has no miles.
    public var averageRatePerMile: Double
    public var fuel: Double
    public var fuelGallons: Double
    public var expenses: Double
    public var penalties: Double
    /// Gross minus fuel, other expenses, and penalties. Paychecks are not subtracted.
    public var net: Double
    /// Weekly goal, or that goal times the weeks overlapping a month. Zero when no goal is set.
    public var goalTarget: Double
    /// Uncapped percent of `goalTarget`. Zero when no goal is set.
    public var goalPercent: Double

    public init(
        gross: Double,
        loadCount: Int,
        loadedMiles: Double,
        emptyMiles: Double,
        drivenMiles: Double,
        averageRatePerMile: Double,
        fuel: Double,
        fuelGallons: Double,
        expenses: Double,
        penalties: Double,
        net: Double,
        goalTarget: Double,
        goalPercent: Double
    ) {
        self.gross = gross
        self.loadCount = loadCount
        self.loadedMiles = loadedMiles
        self.emptyMiles = emptyMiles
        self.drivenMiles = drivenMiles
        self.averageRatePerMile = averageRatePerMile
        self.fuel = fuel
        self.fuelGallons = fuelGallons
        self.expenses = expenses
        self.penalties = penalties
        self.net = net
        self.goalTarget = goalTarget
        self.goalPercent = goalPercent
    }
}

/// One load, already in chronological order and numbered from 1.
public struct PeriodReportLoadBlock: Equatable, Sendable {
    public var number: Int
    public var tripId: String
    /// Date or date span. Printed on the numbered line.
    public var title: String
    public var lines: [PeriodReportLine]
    /// Columns for the printable statement. The plain-text report does not use them.
    public var origin: String
    public var destination: String
    public var shipDate: String
    public var deliveryDate: String
    public var tableMiles: String
    public var tableGross: String
    public var tableRate: String
    /// Pickup instant. The PDF formats this in en_US even when the plain text is not English.
    public var shipAt: Date
    public var deliveredAt: Date?

    public init(
        number: Int,
        tripId: String,
        title: String,
        lines: [PeriodReportLine],
        origin: String = "",
        destination: String = "",
        shipDate: String = "",
        deliveryDate: String = "",
        tableMiles: String = "",
        tableGross: String = "",
        tableRate: String = "",
        shipAt: Date = Date(timeIntervalSince1970: 0),
        deliveredAt: Date? = nil
    ) {
        self.number = number
        self.tripId = tripId
        self.title = title
        self.lines = lines
        self.origin = origin
        self.destination = destination
        self.shipDate = shipDate
        self.deliveryDate = deliveryDate
        self.tableMiles = tableMiles
        self.tableGross = tableGross
        self.tableRate = tableRate
        self.shipAt = shipAt
        self.deliveredAt = deliveredAt
    }
}

/// A finished report. Header, then summary, then numbered loads. Both share formats read this.
public struct PeriodReport: Equatable, Sendable {
    public var brand: String
    public var driverLabel: String
    public var driverName: String?
    public var periodLabel: String
    public var periodTitle: String
    public var generatedLabel: String
    public var generatedOn: String
    public var summaryTitle: String
    public var summary: [PeriodReportLine]
    public var loadsTitle: String
    public var loads: [PeriodReportLoadBlock]
    public var emptyLoadsMessage: String
    public var footer: String
    public var totals: PeriodReportTotals
    public var fileStem: String
    public var language: PeriodReportLanguage
    public var measurementSystem: MeasurementSystem
    public var generatedAt: Date
    public var scope: PeriodReportScope
    public var weekStart: WeekStartDay
    public var timeZoneIdentifier: String

    public init(
        brand: String,
        driverLabel: String,
        driverName: String?,
        periodLabel: String,
        periodTitle: String,
        generatedLabel: String,
        generatedOn: String,
        summaryTitle: String,
        summary: [PeriodReportLine],
        loadsTitle: String,
        loads: [PeriodReportLoadBlock],
        emptyLoadsMessage: String,
        footer: String,
        totals: PeriodReportTotals,
        fileStem: String,
        language: PeriodReportLanguage,
        measurementSystem: MeasurementSystem,
        generatedAt: Date,
        scope: PeriodReportScope,
        weekStart: WeekStartDay,
        timeZoneIdentifier: String
    ) {
        self.brand = brand
        self.driverLabel = driverLabel
        self.driverName = driverName
        self.periodLabel = periodLabel
        self.periodTitle = periodTitle
        self.generatedLabel = generatedLabel
        self.generatedOn = generatedOn
        self.summaryTitle = summaryTitle
        self.summary = summary
        self.loadsTitle = loadsTitle
        self.loads = loads
        self.emptyLoadsMessage = emptyLoadsMessage
        self.footer = footer
        self.totals = totals
        self.fileStem = fileStem
        self.language = language
        self.measurementSystem = measurementSystem
        self.generatedAt = generatedAt
        self.scope = scope
        self.weekStart = weekStart
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}
