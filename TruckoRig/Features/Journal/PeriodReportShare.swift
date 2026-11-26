import UIKit

/// Builds the share payload for the period already selected on the home screen.
enum PeriodReportShare {

    enum Format: Sendable {
        case pdf
        case text
    }

    /// Model built off the main actor. The PDF case still has to be drawn with UIGraphics on main.
    enum Prepared: Sendable {
        case text(String, subject: String)
        case pdf(PeriodReport, PeriodReportStatement, fileStem: String, subject: String)
    }

    /// This week, last week, the chosen week, or this month. Every other home filter is this week.
    static func homePeriod(for filter: JournalViewModel.Filter) -> PeriodReportHomePeriod {
        switch filter {
        case .thisWeek:
            return .thisWeek
        case .lastWeek:
            return .lastWeek
        case .calendarWeek:
            return .chosenWeek
        case .thisMonth:
            return .thisMonth
        case .all, .today, .disputes, .unfinished, .yesterday, .onDate, .dateRange:
            return .other
        }
    }

    static func request(
        scope: PeriodReportScope,
        loads: [Load],
        diesel: [Diesel],
        expenses: [MiscExpense],
        driverName: String,
        weeklyGoal: Double,
        languageCode: String,
        measurementSystem: MeasurementSystem,
        week: TruckingWeek,
        generatedAt: Date
    ) -> PeriodReportRequest {
        PeriodReportRequest(
            driverName: driverName,
            scope: scope,
            loads: loads.map(loadInput),
            fuel: diesel.map {
                PeriodReportFuelFill(totalCost: $0.totalCost, gallons: $0.gallons, date: $0.date)
            },
            expenses: expenses.map {
                PeriodReportExpense(amount: $0.amount, date: $0.date)
            },
            weeklyGoal: weeklyGoal,
            generatedAt: generatedAt,
            language: PeriodReportLanguage.from(code: languageCode),
            measurementSystem: measurementSystem,
            week: week
        )
    }

    /// Text and the statement model. No UIKit.
    static func prepare(_ request: PeriodReportRequest, format: Format) -> Prepared {
        let report = PeriodReportBuilder.build(request)
        let subject = "\(report.brand) — \(report.periodTitle)"
        switch format {
        case .text:
            return .text(PeriodReportText.render(report), subject: subject)
        case .pdf:
            let statement = PeriodReportStatementBuilder.make(report)
            return .pdf(
                report,
                statement,
                fileStem: report.fileStem,
                subject: "\(report.brand) — \(statement.periodLine)"
            )
        }
    }

    static func report(
        scope: PeriodReportScope,
        loads: [Load],
        diesel: [Diesel],
        expenses: [MiscExpense],
        driverName: String,
        weeklyGoal: Double,
        languageCode: String,
        measurementSystem: MeasurementSystem,
        week: TruckingWeek,
        generatedAt: Date
    ) -> PeriodReport {
        PeriodReportBuilder.build(request(
            scope: scope,
            loads: loads,
            diesel: diesel,
            expenses: expenses,
            driverName: driverName,
            weeklyGoal: weeklyGoal,
            languageCode: languageCode,
            measurementSystem: measurementSystem,
            week: week,
            generatedAt: generatedAt
        ))
    }

    static func activity(
        for report: PeriodReport,
        format: Format,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> PeriodReportActivity {
        switch format {
        case .pdf:
            let statement = PeriodReportStatementBuilder.make(report)
            return try activity(for: .pdf(
                report,
                statement,
                fileStem: report.fileStem,
                subject: "\(report.brand) — \(statement.periodLine)"
            ), directory: directory)
        case .text:
            return try activity(for: .text(
                PeriodReportText.render(report),
                subject: "\(report.brand) — \(report.periodTitle)"
            ), directory: directory)
        }
    }

    /// Draws a PDF on the caller. Call this on the main thread. Text does not touch UIKit.
    static func activity(
        for prepared: Prepared,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> PeriodReportActivity {
        switch prepared {
        case .pdf(let report, let statement, let fileStem, let subject):
            let url = directory.appendingPathComponent("\(fileStem).pdf")
            try PeriodReportPDF.data(for: report, statement: statement).write(to: url, options: .atomic)
            return PeriodReportActivity(items: [PeriodReportActivityItem(file: url, subject: subject)])
        case .text(let text, let subject):
            return PeriodReportActivity(items: [
                PeriodReportActivityItem(text: text, subject: subject),
            ])
        }
    }

    private static func loadInput(_ load: Load) -> PeriodReportLoadInput {
        let notes = (load.stops ?? []).compactMap { stop -> String? in
            let note = stop.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return note.isEmpty ? nil : note
        }
        return PeriodReportLoadInput(
            tripId: load.tripId,
            rate: load.totalRate,
            loadedMiles: load.totalMiles,
            emptyMiles: max(0, load.deadheadMiles),
            filedOn: load.date,
            pickupAt: load.firstPickupAt,
            deliveryAt: load.lastDeliveryAt,
            finishAt: load.actualFinishDate,
            weekNumber: load.weekNumber,
            year: load.year,
            origin: load.pointA ?? "",
            destination: load.pointB ?? "",
            equipmentCode: load.equipmentType,
            source: LoadSourceTag.detect(tripId: load.tripId, rawMessage: load.rawMessage),
            isDispute: load.isDispute,
            disputeCompleted: load.disputeCompleted,
            notes: notes,
            penalties: (load.penalties ?? []).map { PeriodReportPenalty(summary: $0.summary, amount: $0.amount) },
            isCancelled: load.isCancelled
        )
    }
}

struct PeriodReportActivity: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Share payload that also sets the mail subject to the period title.
final class PeriodReportActivityItem: NSObject, UIActivityItemSource {
    private let text: String?
    private let file: URL?
    private let subjectLine: String

    init(text: String, subject: String) {
        self.text = text
        self.file = nil
        self.subjectLine = subject
    }

    init(file: URL, subject: String) {
        self.text = nil
        self.file = file
        self.subjectLine = subject
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        text ?? file ?? ""
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        text ?? file
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subjectLine
    }
}
