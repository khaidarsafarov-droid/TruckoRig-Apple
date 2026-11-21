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

    public init(number: Int, tripId: String, title: String, lines: [PeriodReportLine]) {
        self.number = number
        self.tripId = tripId
        self.title = title
        self.lines = lines
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
        fileStem: String
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
    }
}

/// Plain-text report for Messages, WhatsApp, and Telegram.
///
/// Sections stay in a fixed order — header, summary, numbered loads — so the Android report
/// can use the same reading order. Loads are separated by a blank line and a rule.
public enum PeriodReportText {
    public static func render(_ report: PeriodReport) -> String {
        var lines: [String] = [report.brand]
        if let driverName = report.driverName {
            lines.append("\(report.driverLabel): \(driverName)")
        }
        lines.append("\(report.periodLabel): \(report.periodTitle)")
        lines.append("\(report.generatedLabel): \(report.generatedOn)")
        lines.append("")
        lines.append(report.summaryTitle)
        lines.append(contentsOf: report.summary.map { "\($0.label): \($0.value)" })
        lines.append("")
        lines.append(report.loadsTitle)
        lines.append("")
        if report.loads.isEmpty {
            lines.append(report.emptyLoadsMessage)
        } else {
            for (index, load) in report.loads.enumerated() {
                if index > 0 {
                    lines.append("")
                    lines.append("------------")
                    lines.append("")
                }
                lines.append("\(load.number). \(load.title)")
                lines.append(contentsOf: load.lines.map { "\($0.label): \($0.value)" })
            }
        }
        lines.append("")
        lines.append(report.footer)
        return lines.joined(separator: "\n")
    }
}

public enum PeriodReportBuilder {

    /// The week or month that contains `day`.
    public static func scope(kind: PeriodReportKind, containing day: Date, week: TruckingWeek) -> PeriodReportScope {
        switch kind {
        case .week:
            return .week(week.week(for: day))
        case .month:
            let parts = week.calendar.dateComponents([.year, .month], from: day)
            return .month(year: parts.year ?? 0, month: parts.month ?? 0)
        }
    }

    public static func periodTitle(scope: PeriodReportScope, week: TruckingWeek, language: PeriodReportLanguage) -> String {
        let copy = PeriodReportCopy.resolve(language)
        return title(scope: scope, week: week, locale: language.locale, copy: copy)
    }

    public static func build(_ request: PeriodReportRequest) -> PeriodReport {
        let copy = PeriodReportCopy.resolve(request.language)
        let calendar = request.week.calendar
        let window = dateWindow(scope: request.scope, week: request.week)
        let included = request.loads
            .filter { includes($0, scope: request.scope, window: window, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.sortDate != rhs.sortDate { return lhs.sortDate < rhs.sortDate }
                return lhs.tripId < rhs.tripId
            }

        let totals = summarize(
            loads: included,
            fuel: request.fuel,
            expenses: request.expenses,
            weeklyGoal: request.weeklyGoal,
            scope: request.scope,
            window: window,
            week: request.week
        )
        let system = request.measurementSystem
        let summary = summaryLines(totals: totals, copy: copy, system: system)
        let blocks = included.enumerated().map { offset, load in
            loadBlock(number: offset + 1, load: load, copy: copy, system: system, calendar: calendar, locale: request.language.locale)
        }
        let driver = request.driverName.trimmingCharacters(in: .whitespacesAndNewlines)
        return PeriodReport(
            brand: copy.brand,
            driverLabel: copy.driver,
            driverName: driver.isEmpty ? nil : driver,
            periodLabel: copy.period,
            periodTitle: title(scope: request.scope, week: request.week, locale: request.language.locale, copy: copy),
            generatedLabel: copy.generated,
            generatedOn: mediumDate(request.generatedAt, calendar: calendar, locale: request.language.locale),
            summaryTitle: copy.summary,
            summary: summary,
            loadsTitle: copy.loadsSection,
            loads: blocks,
            emptyLoadsMessage: copy.emptyLoads,
            footer: copy.footer,
            totals: totals,
            fileStem: fileStem(scope: request.scope)
        )
    }

    // MARK: - Window

    private struct DateWindow {
        var start: Date
        var endExclusive: Date
    }

    private static func dateWindow(scope: PeriodReportScope, week: TruckingWeek) -> DateWindow? {
        switch scope {
        case .week(let ref):
            guard let range = week.dateRange(of: ref) else { return nil }
            return DateWindow(start: range.lowerBound, endExclusive: range.upperBound)
        case .month(let year, let month):
            var parts = DateComponents()
            parts.year = year
            parts.month = month
            parts.day = 1
            guard let start = week.calendar.date(from: parts),
                  let end = week.calendar.date(byAdding: .month, value: 1, to: week.calendar.startOfDay(for: start))
            else { return nil }
            return DateWindow(start: week.calendar.startOfDay(for: start), endExclusive: end)
        }
    }

    private static func includes(
        _ load: PeriodReportLoadInput,
        scope: PeriodReportScope,
        window: DateWindow?,
        calendar: Calendar
    ) -> Bool {
        switch scope {
        case .week(let ref):
            return load.weekNumber == ref.weekNumber && load.year == ref.year
        case .month:
            guard let window else { return false }
            let begin = load.pickupAt ?? load.filedOn
            let finish = load.finishAt ?? load.deliveryAt ?? begin
            let first = calendar.startOfDay(for: min(begin, finish))
            let last = calendar.startOfDay(for: max(begin, finish))
            return first < window.endExclusive && last >= window.start
        }
    }

    // MARK: - Totals

    private static func summarize(
        loads: [PeriodReportLoadInput],
        fuel: [PeriodReportFuelFill],
        expenses: [PeriodReportExpense],
        weeklyGoal: Double,
        scope: PeriodReportScope,
        window: DateWindow?,
        week: TruckingWeek
    ) -> PeriodReportTotals {
        let gross = money(loads.reduce(0) { $0 + $1.rate })
        let loaded = loads.reduce(0) { $0 + $1.loadedMiles }
        let empty = loads.reduce(0) { $0 + max(0, $1.emptyMiles) }
        let driven = loaded + empty
        let penalties = money(loads.reduce(0) { total, load in
            total + load.penalties.reduce(0) { $0 + $1.amount }
        })
        let fills = fuel.filter { contains($0.date, window) }
        let fuelCost = money(fills.reduce(0) { $0 + $1.totalCost })
        let gallons = fills.reduce(0) { $0 + max(0, $1.gallons) }
        let expenseTotal = money(expenses.filter { contains($0.date, window) }.reduce(0) { $0 + $1.amount })
        let net = money(gross - fuelCost - expenseTotal - penalties)
        let rate = driven > 0 ? gross / driven : 0
        let goal = goalTarget(weeklyGoal: weeklyGoal, scope: scope, window: window, week: week)
        let percent = goal > 0 ? gross / goal * 100 : 0
        return PeriodReportTotals(
            gross: gross,
            loadCount: loads.count,
            loadedMiles: loaded,
            emptyMiles: empty,
            drivenMiles: driven,
            averageRatePerMile: rate,
            fuel: fuelCost,
            fuelGallons: gallons,
            expenses: expenseTotal,
            penalties: penalties,
            net: net,
            goalTarget: goal,
            goalPercent: percent
        )
    }

    /// A week uses the weekly goal. A month uses that goal once per overlapping trucking week.
    private static func goalTarget(
        weeklyGoal: Double,
        scope: PeriodReportScope,
        window: DateWindow?,
        week: TruckingWeek
    ) -> Double {
        guard weeklyGoal > 0 else { return 0 }
        switch scope {
        case .week:
            return money(weeklyGoal)
        case .month:
            guard let window else { return money(weeklyGoal) }
            return money(weeklyGoal * Double(weeksOverlapping(window, week: week)))
        }
    }

    private static func weeksOverlapping(_ window: DateWindow, week: TruckingWeek) -> Int {
        guard window.endExclusive > window.start else { return 1 }
        let lastInstant = window.endExclusive.addingTimeInterval(-1)
        var cursor = week.week(for: window.start)
        let last = week.week(for: lastInstant)
        var count = 0
        var guardrail = 0
        while cursor <= last && guardrail < 8 {
            count += 1
            let next = week.shift(cursor, by: 1)
            if next <= cursor { break }
            cursor = next
            guardrail += 1
        }
        return max(count, 1)
    }

    private static func contains(_ date: Date, _ window: DateWindow?) -> Bool {
        guard let window else { return false }
        return date >= window.start && date < window.endExclusive
    }

    private static func money(_ value: Double) -> Double {
        MoneyCents.fromDollars(value).dollars
    }

    // MARK: - Lines

    private static func summaryLines(
        totals: PeriodReportTotals,
        copy: PeriodReportCopy,
        system: MeasurementSystem
    ) -> [PeriodReportLine] {
        var lines = [
            PeriodReportLine(label: copy.gross, value: dollars(totals.gross)),
            PeriodReportLine(label: copy.loadCount, value: "\(totals.loadCount)"),
            PeriodReportLine(label: copy.distance(system), value: distance(totals.drivenMiles, system: system)),
            PeriodReportLine(label: copy.loadedDistance(system), value: distance(totals.loadedMiles, system: system)),
            PeriodReportLine(label: copy.emptyDistance(system), value: distance(totals.emptyMiles, system: system)),
            PeriodReportLine(label: copy.averageRate, value: rate(totals.averageRatePerMile, system: system)),
            PeriodReportLine(label: copy.fuel, value: fuelValue(totals, copy: copy, system: system)),
            PeriodReportLine(label: copy.expenses, value: dollars(totals.expenses)),
            PeriodReportLine(label: copy.penalties, value: dollars(totals.penalties)),
            PeriodReportLine(label: copy.net, value: dollars(totals.net)),
        ]
        if totals.goalTarget > 0 {
            lines.append(PeriodReportLine(label: copy.weeklyGoal, value: dollars(totals.goalTarget)))
            lines.append(PeriodReportLine(
                label: copy.goalProgress,
                value: copy.goalProgressValue(
                    percent: Int(totals.goalPercent.rounded()),
                    gross: dollars(totals.gross),
                    target: dollars(totals.goalTarget)
                )
            ))
        }
        return lines
    }

    private static func loadBlock(
        number: Int,
        load: PeriodReportLoadInput,
        copy: PeriodReportCopy,
        system: MeasurementSystem,
        calendar: Calendar,
        locale: Locale
    ) -> PeriodReportLoadBlock {
        var lines: [PeriodReportLine] = []
        let origin = load.origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = load.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if !origin.isEmpty || !destination.isEmpty {
            let route: String
            if !origin.isEmpty && !destination.isEmpty {
                route = "\(origin) → \(destination)"
            } else {
                route = origin.isEmpty ? destination : origin
            }
            lines.append(PeriodReportLine(label: copy.route, value: route))
        }
        let trip = load.tripId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trip.isEmpty {
            lines.append(PeriodReportLine(label: copy.loadNumber, value: trip))
        }
        lines.append(PeriodReportLine(label: copy.distance(system), value: distance(load.drivenMiles, system: system)))
        lines.append(PeriodReportLine(label: copy.loadedDistance(system), value: distance(load.loadedMiles, system: system)))
        lines.append(PeriodReportLine(label: copy.emptyDistance(system), value: distance(max(0, load.emptyMiles), system: system)))
        lines.append(PeriodReportLine(label: copy.rate, value: dollars(load.rate)))
        let perMile = load.drivenMiles > 0 ? load.rate / load.drivenMiles : 0
        lines.append(PeriodReportLine(label: copy.ratePerDistance(system), value: rate(perMile, system: system)))
        lines.append(PeriodReportLine(label: copy.status, value: status(of: load, copy: copy)))
        lines.append(PeriodReportLine(label: copy.source, value: sourceName(load.source, copy: copy)))
        if let equipment = copy.equipmentName(load.equipmentCode) {
            lines.append(PeriodReportLine(label: copy.equipment, value: equipment))
        }
        let notes = load.notes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !notes.isEmpty {
            lines.append(PeriodReportLine(label: copy.notes, value: notes.joined(separator: " · ")))
        }
        let penaltyLines = load.penalties.filter { $0.amount != 0 || !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !penaltyLines.isEmpty {
            let text = penaltyLines.map { penalty in
                let name = penalty.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                let amount = dollars(penalty.amount)
                return name.isEmpty ? amount : "\(name) \(amount)"
            }.joined(separator: "; ")
            lines.append(PeriodReportLine(label: copy.penalties, value: text))
        }
        return PeriodReportLoadBlock(
            number: number,
            tripId: trip,
            title: dateSpan(of: load, calendar: calendar, locale: locale),
            lines: lines
        )
    }

    private static func status(of load: PeriodReportLoadInput, copy: PeriodReportCopy) -> String {
        if load.isDispute && !load.disputeCompleted { return copy.statusDisputeOpen }
        if load.isDispute && load.disputeCompleted { return copy.statusDisputeSettled }
        if load.deliveryAt == nil && load.finishAt == nil { return copy.statusInProgress }
        return copy.statusDelivered
    }

    private static func sourceName(_ source: LoadSourceTag, copy: PeriodReportCopy) -> String {
        switch source {
        case .relay: return copy.sourceRelay
        case .manual: return copy.sourceManual
        case .broker: return copy.sourceBroker
        }
    }

    private static func fuelValue(
        _ totals: PeriodReportTotals,
        copy: PeriodReportCopy,
        system: MeasurementSystem
    ) -> String {
        let amount = dollars(totals.fuel)
        guard totals.fuelGallons > 0 else { return amount }
        let shown = MeasurementUnits.displayVolume(totals.fuelGallons, system: system)
        let digits = abs(shown.rounded() - shown) < 0.05 ? 0 : 1
        return "\(amount) · \(USMoneyFormat.number(shown, fractionDigits: digits)) \(copy.volumeUnit(system))"
    }

    private static func dollars(_ value: Double) -> String {
        USMoneyFormat.currency(value, fractionDigits: 2)
    }

    private static func distance(_ miles: Double, system: MeasurementSystem) -> String {
        USMoneyFormat.miles(miles, system: system)
    }

    private static func rate(_ perMile: Double, system: MeasurementSystem) -> String {
        guard perMile > 0 else { return "—" }
        return USMoneyFormat.rpmPerMile(perMile, system: system)
    }

    // MARK: - Dates and names

    private static func title(
        scope: PeriodReportScope,
        week: TruckingWeek,
        locale: Locale,
        copy: PeriodReportCopy
    ) -> String {
        switch scope {
        case .week(let ref):
            let range = WeekLabelFormatter(week: week, locale: locale).label(for: ref)
            return "\(copy.week) \(ref.weekNumber) · \(range)"
        case .month(let year, let month):
            guard let window = dateWindow(scope: scope, week: week) else { return "\(year)-\(month)" }
            let last = week.calendar.date(byAdding: .day, value: -1, to: window.endExclusive) ?? window.start
            let name = monthName(window.start, calendar: week.calendar, locale: locale)
            let span = dateRange(window.start, last, calendar: week.calendar, locale: locale)
            return "\(name) · \(span)"
        }
    }

    private static func dateSpan(of load: PeriodReportLoadInput, calendar: Calendar, locale: Locale) -> String {
        let start = load.pickupAt ?? load.filedOn
        let end = load.finishAt ?? load.deliveryAt ?? start
        if calendar.isDate(start, inSameDayAs: end) {
            return mediumDate(start, calendar: calendar, locale: locale)
        }
        return dateRange(start, end, calendar: calendar, locale: locale)
    }

    private static func dateRange(_ start: Date, _ end: Date, calendar: Calendar, locale: Locale) -> String {
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        if sameYear {
            return "\(monthDay(start, calendar: calendar, locale: locale)) – \(monthDay(end, calendar: calendar, locale: locale)), \(calendar.component(.year, from: end))"
        }
        return "\(mediumDate(start, calendar: calendar, locale: locale)) – \(mediumDate(end, calendar: calendar, locale: locale))"
    }

    private static func monthDay(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = dateFormatter(calendar: calendar, locale: locale, template: "MMMd")
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    private static func mediumDate(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        dateFormatter(calendar: calendar, locale: locale, template: "MMMdyyyy").string(from: date)
    }

    private static func monthName(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        dateFormatter(calendar: calendar, locale: locale, template: "MMMMy").string(from: date)
    }

    private static func dateFormatter(calendar: Calendar, locale: Locale, template: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    private static func fileStem(scope: PeriodReportScope) -> String {
        switch scope {
        case .week(let ref):
            return "TruckoRig-week-\(ref.weekNumber)-\(ref.year)"
        case .month(let year, let month):
            return String(format: "TruckoRig-%04d-%02d", year, month)
        }
    }
}

/// Captions baked into the report. The share sheet's chrome lives in the string catalog;
/// the file a dispatcher receives cannot depend on that catalog being loaded.
struct PeriodReportCopy: Equatable, Sendable {
    var brand: String
    var driver: String
    var period: String
    var generated: String
    var summary: String
    var loadsSection: String
    var gross: String
    var loadCount: String
    var miles: String
    var kilometers: String
    var loadedMiles: String
    var loadedKilometers: String
    var emptyMiles: String
    var emptyKilometers: String
    var averageRate: String
    var fuel: String
    var expenses: String
    var penalties: String
    var net: String
    var weeklyGoal: String
    var goalProgress: String
    var goalOf: String
    var route: String
    var loadNumber: String
    var rate: String
    var ratePerMile: String
    var ratePerKilometer: String
    var status: String
    var source: String
    var equipment: String
    var notes: String
    var statusInProgress: String
    var statusDelivered: String
    var statusDisputeOpen: String
    var statusDisputeSettled: String
    var sourceRelay: String
    var sourceManual: String
    var sourceBroker: String
    var emptyLoads: String
    var footer: String
    var week: String
    var gallons: String
    var liters: String
    var equipmentNames: [String: String]

    func distance(_ system: MeasurementSystem) -> String {
        system == .kilometers ? kilometers : miles
    }

    func loadedDistance(_ system: MeasurementSystem) -> String {
        system == .kilometers ? loadedKilometers : loadedMiles
    }

    func emptyDistance(_ system: MeasurementSystem) -> String {
        system == .kilometers ? emptyKilometers : emptyMiles
    }

    func ratePerDistance(_ system: MeasurementSystem) -> String {
        system == .kilometers ? ratePerKilometer : ratePerMile
    }

    func volumeUnit(_ system: MeasurementSystem) -> String {
        system == .kilometers ? liters : gallons
    }

    func goalProgressValue(percent: Int, gross: String, target: String) -> String {
        "\(percent)% (\(gross) \(goalOf) \(target))"
    }

    func equipmentName(_ code: String?) -> String? {
        guard let code else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let known = EquipmentType.fromStorage(trimmed) {
            return equipmentNames[known.rawValue] ?? known.rawValue
        }
        return trimmed
    }

    static func resolve(_ language: PeriodReportLanguage) -> PeriodReportCopy {
        switch language {
        case .english: return english
        case .russian: return russian
        case .french: return french
        case .spanish: return spanish
        }
    }

    static let english = PeriodReportCopy(
        brand: "TruckoRig",
        driver: "Driver",
        period: "Period",
        generated: "Generated",
        summary: "Summary",
        loadsSection: "Loads",
        gross: "Gross revenue",
        loadCount: "Number of loads",
        miles: "Miles",
        kilometers: "Kilometers",
        loadedMiles: "Loaded miles",
        loadedKilometers: "Loaded kilometers",
        emptyMiles: "Empty miles",
        emptyKilometers: "Empty kilometers",
        averageRate: "Average rate",
        fuel: "Fuel",
        expenses: "Expenses",
        penalties: "Penalties",
        net: "Net",
        weeklyGoal: "Goal",
        goalProgress: "Goal progress",
        goalOf: "of",
        route: "Route",
        loadNumber: "Load #",
        rate: "Rate",
        ratePerMile: "Rate per mile",
        ratePerKilometer: "Rate per kilometer",
        status: "Status",
        source: "Source",
        equipment: "Equipment",
        notes: "Notes",
        statusInProgress: "In progress",
        statusDelivered: "Delivered",
        statusDisputeOpen: "Dispute open",
        statusDisputeSettled: "Dispute settled",
        sourceRelay: "Amazon Relay",
        sourceManual: "Manual",
        sourceBroker: "Broker",
        emptyLoads: "No loads in this period.",
        footer: "Only on this device",
        week: "Week",
        gallons: "gal",
        liters: "L",
        equipmentNames: [
            "DRY_VAN": "Dry van",
            "REEFER": "Reefer",
            "FLATBED": "Flatbed",
            "POWER_ONLY": "Power only",
            "AMAZON_RELAY": "Amazon Relay",
            "BOX_TRUCK": "Box truck",
            "CARGO_VAN": "Cargo van",
            "OTHER": "Other",
        ]
    )

    static let russian = PeriodReportCopy(
        brand: "TruckoRig",
        driver: "Водитель",
        period: "Период",
        generated: "Создан",
        summary: "Сводка",
        loadsSection: "Грузы",
        gross: "Валовая выручка",
        loadCount: "Число грузов",
        miles: "Мили",
        kilometers: "Километры",
        loadedMiles: "Мили с грузом",
        loadedKilometers: "Километры с грузом",
        emptyMiles: "Порожние мили",
        emptyKilometers: "Порожние километры",
        averageRate: "Средняя ставка",
        fuel: "Топливо",
        expenses: "Расходы",
        penalties: "Штрафы",
        net: "Чистыми",
        weeklyGoal: "Цель",
        goalProgress: "Прогресс цели",
        goalOf: "из",
        route: "Маршрут",
        loadNumber: "№ груза",
        rate: "Ставка",
        ratePerMile: "Ставка за милю",
        ratePerKilometer: "Ставка за километр",
        status: "Статус",
        source: "Источник",
        equipment: "Оборудование",
        notes: "Заметки",
        statusInProgress: "В пути",
        statusDelivered: "Доставлен",
        statusDisputeOpen: "Спор открыт",
        statusDisputeSettled: "Спор закрыт",
        sourceRelay: "Amazon Relay",
        sourceManual: "Вручную",
        sourceBroker: "Брокер",
        emptyLoads: "В этом периоде нет грузов.",
        footer: "Только на этом устройстве",
        week: "Неделя",
        gallons: "гал",
        liters: "л",
        equipmentNames: [
            "DRY_VAN": "Сухой фургон",
            "REEFER": "Рефрижератор",
            "FLATBED": "Площадка",
            "POWER_ONLY": "Только тягач",
            "AMAZON_RELAY": "Amazon Relay",
            "BOX_TRUCK": "Фургон",
            "CARGO_VAN": "Грузовой фургон",
            "OTHER": "Другое",
        ]
    )

    static let french = PeriodReportCopy(
        brand: "TruckoRig",
        driver: "Conducteur",
        period: "Période",
        generated: "Créé le",
        summary: "Sommaire",
        loadsSection: "Voyages",
        gross: "Revenu brut",
        loadCount: "Nombre de voyages",
        miles: "Milles",
        kilometers: "Kilomètres",
        loadedMiles: "Milles chargés",
        loadedKilometers: "Kilomètres chargés",
        emptyMiles: "Milles à vide",
        emptyKilometers: "Kilomètres à vide",
        averageRate: "Taux moyen",
        fuel: "Carburant",
        expenses: "Dépenses",
        penalties: "Pénalités",
        net: "Net",
        weeklyGoal: "Objectif",
        goalProgress: "Progression",
        goalOf: "sur",
        route: "Trajet",
        loadNumber: "N° de voyage",
        rate: "Taux",
        ratePerMile: "Taux au mille",
        ratePerKilometer: "Taux au kilomètre",
        status: "Statut",
        source: "Source",
        equipment: "Équipement",
        notes: "Notes",
        statusInProgress: "En cours",
        statusDelivered: "Livré",
        statusDisputeOpen: "Litige ouvert",
        statusDisputeSettled: "Litige réglé",
        sourceRelay: "Amazon Relay",
        sourceManual: "Manuel",
        sourceBroker: "Courtier",
        emptyLoads: "Aucun voyage pour cette période.",
        footer: "Uniquement sur cet appareil",
        week: "Semaine",
        gallons: "gal",
        liters: "L",
        equipmentNames: [
            "DRY_VAN": "Fourgon sec",
            "REEFER": "Frigorifique",
            "FLATBED": "Plateau",
            "POWER_ONLY": "Tracteur seul",
            "AMAZON_RELAY": "Amazon Relay",
            "BOX_TRUCK": "Camion fourgon",
            "CARGO_VAN": "Fourgonnette",
            "OTHER": "Autre",
        ]
    )

    static let spanish = PeriodReportCopy(
        brand: "TruckoRig",
        driver: "Conductor",
        period: "Período",
        generated: "Generado",
        summary: "Resumen",
        loadsSection: "Cargas",
        gross: "Ingreso bruto",
        loadCount: "Número de cargas",
        miles: "Millas",
        kilometers: "Kilómetros",
        loadedMiles: "Millas cargadas",
        loadedKilometers: "Kilómetros cargados",
        emptyMiles: "Millas vacías",
        emptyKilometers: "Kilómetros vacíos",
        averageRate: "Tarifa media",
        fuel: "Combustible",
        expenses: "Gastos",
        penalties: "Penalizaciones",
        net: "Neto",
        weeklyGoal: "Meta",
        goalProgress: "Progreso de la meta",
        goalOf: "de",
        route: "Ruta",
        loadNumber: "N.º de carga",
        rate: "Tarifa",
        ratePerMile: "Tarifa por milla",
        ratePerKilometer: "Tarifa por kilómetro",
        status: "Estado",
        source: "Origen",
        equipment: "Equipo",
        notes: "Notas",
        statusInProgress: "En curso",
        statusDelivered: "Entregada",
        statusDisputeOpen: "Disputa abierta",
        statusDisputeSettled: "Disputa cerrada",
        sourceRelay: "Amazon Relay",
        sourceManual: "Manual",
        sourceBroker: "Bróker",
        emptyLoads: "No hay cargas en este período.",
        footer: "Solo en este dispositivo",
        week: "Semana",
        gallons: "gal",
        liters: "L",
        equipmentNames: [
            "DRY_VAN": "Caja seca",
            "REEFER": "Refrigerado",
            "FLATBED": "Plataforma",
            "POWER_ONLY": "Solo tracto",
            "AMAZON_RELAY": "Amazon Relay",
            "BOX_TRUCK": "Camión caja",
            "CARGO_VAN": "Furgoneta",
            "OTHER": "Otro",
        ]
    )
}
