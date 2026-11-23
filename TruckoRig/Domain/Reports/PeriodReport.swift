import Foundation

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

    /// Period for the home share button. A week or month filter wins; every other filter is this week.
    public static func scope(
        home: PeriodReportHomePeriod,
        selectedDay: Date,
        now: Date,
        week: TruckingWeek
    ) -> PeriodReportScope {
        switch home {
        case .thisWeek, .other:
            return .week(week.currentWeek(now: now))
        case .lastWeek:
            return .week(week.previousWeek(now: now))
        case .chosenWeek:
            return .week(week.week(for: selectedDay))
        case .thisMonth:
            return scope(kind: .month, containing: now, week: week)
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
            fileStem: fileStem(scope: request.scope),
            language: request.language,
            measurementSystem: system,
            generatedAt: request.generatedAt,
            scope: request.scope,
            weekStart: request.week.weekStart,
            timeZoneIdentifier: request.week.calendar.timeZone.identifier
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
        let ship = load.pickupAt ?? load.filedOn
        let delivery = load.finishAt ?? load.deliveryAt
        return PeriodReportLoadBlock(
            number: number,
            tripId: trip,
            title: dateSpan(of: load, calendar: calendar, locale: locale),
            lines: lines,
            origin: origin,
            destination: destination,
            shipDate: shortDate(ship, calendar: calendar, locale: locale),
            deliveryDate: delivery.map { shortDate($0, calendar: calendar, locale: locale) } ?? "",
            tableMiles: milesNumber(load.drivenMiles, system: system),
            tableGross: dollars(load.rate),
            tableRate: perMile > 0 ? rateAmount(perMile, system: system) : "—",
            shipAt: ship,
            deliveredAt: delivery
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

    /// Dollar amount only. The statement column header already says Rate/mi.
    static func rateAmount(_ perMile: Double, system: MeasurementSystem) -> String {
        let shown = MeasurementUnits.displayPerDistance(perMile, system: system)
        return String(format: "$%.2f", locale: Locale(identifier: "en_US"), shown)
    }

    static func milesNumber(_ miles: Double, system: MeasurementSystem) -> String {
        let shown = MeasurementUnits.displayDistance(miles, system: system)
        let digits = abs(shown.rounded() - shown) < 0.05 ? 0 : 1
        return USMoneyFormat.number(shown, fractionDigits: digits)
    }

    /// en_US numeric date for the PDF, independent of the plain-text language.
    static func englishShortDate(_ date: Date, week: TruckingWeek) -> String {
        shortDate(date, calendar: week.calendar, locale: Locale(identifier: "en_US"))
    }

    static func englishMediumDate(_ date: Date, week: TruckingWeek) -> String {
        mediumDate(date, calendar: week.calendar, locale: Locale(identifier: "en_US"))
    }

    static func englishWeek(from report: PeriodReport) -> TruckingWeek {
        let zone = TimeZone(identifier: report.timeZoneIdentifier) ?? .current
        return TruckingWeek(weekStart: report.weekStart, timeZone: zone)
    }

    private static func shortDate(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let code = locale.language.languageCode?.identifier ?? "en"
        switch code {
        case "ru":
            formatter.dateFormat = "dd.MM.yy"
        case "fr", "es":
            formatter.dateFormat = "dd/MM/yy"
        default:
            formatter.dateFormat = "M/d/yy"
        }
        return formatter.string(from: date)
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
