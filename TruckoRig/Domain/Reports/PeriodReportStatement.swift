import Foundation

/// Printable load statement. One table, then a short summary. No fuel, expenses, or deductions.
///
/// The plain-text share keeps the longer report. This is only the PDF layout, shared with Android:
/// header, load rows, a total row, then summary totals.
public struct PeriodReportStatement: Equatable, Sendable {
    public var title: String
    public var driverName: String?
    public var periodLine: String
    public var generatedLine: String
    public var columns: [String]
    public var rows: [[String]]
    public var totalLabel: String
    /// Same width as `columns`. Blank cells stay empty.
    public var totalRow: [String]
    public var summaryTitle: String
    public var summary: [PeriodReportLine]
    public var emptyMessage: String
    public var footer: String

    public init(
        title: String,
        driverName: String?,
        periodLine: String,
        generatedLine: String,
        columns: [String],
        rows: [[String]],
        totalLabel: String,
        totalRow: [String],
        summaryTitle: String,
        summary: [PeriodReportLine],
        emptyMessage: String,
        footer: String
    ) {
        self.title = title
        self.driverName = driverName
        self.periodLine = periodLine
        self.generatedLine = generatedLine
        self.columns = columns
        self.rows = rows
        self.totalLabel = totalLabel
        self.totalRow = totalRow
        self.summaryTitle = summaryTitle
        self.summary = summary
        self.emptyMessage = emptyMessage
        self.footer = footer
    }
}

public enum PeriodReportStatementBuilder {

    /// Always English, including when the journal that produced `report` is Russian.
    public static func make(_ report: PeriodReport) -> PeriodReportStatement {
        let copy = PeriodReportCopy.english
        let system = report.measurementSystem
        let week = PeriodReportBuilder.englishWeek(from: report)
        let columns = [
            copy.loadNumber,
            copy.originHeader,
            copy.destinationHeader,
            copy.shipHeader,
            copy.deliveryHeader,
            copy.distance(system),
            copy.grossHeader,
            copy.rateColumn(system),
        ]
        let rows = report.loads.map { load in
            [
                load.isCancelled ? "\(load.tripId) (TONU)" : load.tripId,
                load.origin,
                load.destination,
                PeriodReportBuilder.englishShortDate(load.shipAt, week: week),
                load.deliveredAt.map { PeriodReportBuilder.englishShortDate($0, week: week) } ?? "",
                load.tableMiles,
                load.tableGross,
                load.tableRate,
            ]
        }
        let totals = report.totals
        let rate = totals.drivenMiles > 0 ? totals.gross / totals.drivenMiles : 0
        var totalRow = Array(repeating: "", count: columns.count)
        totalRow[0] = copy.total
        totalRow[5] = PeriodReportBuilder.milesNumber(totals.drivenMiles, system: system)
        totalRow[6] = USMoneyFormat.currency(totals.gross, fractionDigits: 2)
        totalRow[7] = rate > 0 ? PeriodReportBuilder.rateAmount(rate, system: system) : "—"
        let summary = [
            PeriodReportLine(label: copy.loadsTotal, value: "\(totals.loadCount)"),
            PeriodReportLine(label: copy.grossTotal, value: USMoneyFormat.currency(totals.gross, fractionDigits: 2)),
            PeriodReportLine(label: copy.milesTotal, value: USMoneyFormat.miles(totals.drivenMiles, system: system)),
            PeriodReportLine(
                label: copy.averageRate,
                value: rate > 0 ? USMoneyFormat.rpmPerMile(rate, system: system) : "—"
            ),
        ]
        return PeriodReportStatement(
            title: copy.statementTitle,
            driverName: report.driverName,
            periodLine: PeriodReportBuilder.periodTitle(scope: report.scope, week: week, language: .english),
            generatedLine: "\(copy.generated): \(PeriodReportBuilder.englishMediumDate(report.generatedAt, week: week))",
            columns: columns,
            rows: rows,
            totalLabel: copy.total,
            totalRow: totalRow,
            summaryTitle: copy.summary,
            summary: summary,
            emptyMessage: copy.emptyLoads,
            footer: copy.footer
        )
    }
}
