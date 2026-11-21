import SwiftUI
import UIKit

/// Chooses a week or month and a file format, then opens the system share sheet.
///
/// The journal filter seeds the period: this week, last week, a chosen week, or this month.
/// Any other filter opens on the current week, and the picker can move to another week or month.
struct PeriodReportShareSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var kind: PeriodReportKind
    @State private var day: Date
    @State private var format: ShareFormat = .pdf
    @State private var activity: ReportActivity?
    @State private var errorMessage: String?

    init(kind: PeriodReportKind, day: Date) {
        _kind = State(initialValue: kind)
        _day = State(initialValue: day)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.standard) {
                    periodCard
                    Picker("journal.share.period", selection: $kind) {
                        Text("journal.share.week").tag(PeriodReportKind.week)
                        Text("journal.share.month").tag(PeriodReportKind.month)
                    }
                    .pickerStyle(.segmented)

                    DatePicker("journal.share.date", selection: $day, displayedComponents: .date)
                    Text("journal.share.hint")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)

                    Picker("journal.share.format", selection: $format) {
                        ForEach(ShareFormat.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("journal.share.privacy")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)

                    SoftButton(title: "journal.share", systemImage: "square.and.arrow.up", action: share)
                }
                .padding(Spacing.standard)
            }
            .forestBackground()
            .navigationTitle("journal.share.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $activity) { item in
            ShareSheet(items: item.items)
        }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private var periodCard: some View {
        let current = report
        return VStack(alignment: .leading, spacing: 6) {
            Text(current.periodTitle)
                .font(.appBodyMedium)
                .foregroundStyle(Color.heroText)
            ForEach(Array(current.summary.prefix(3).enumerated()), id: \.offset) { _, line in
                Text("\(line.label): \(line.value)")
                    .font(.appCaption)
                    .foregroundStyle(Color.heroTextMuted)
            }
            if current.loads.isEmpty {
                Text(current.emptyLoadsMessage)
                    .font(.appCaption)
                    .foregroundStyle(Color.heroTextMuted)
            }
        }
        .padding(Spacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroGradient())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var report: PeriodReport {
        let settings = appState.settings
        let week = settings.truckingWeek
        return PeriodReportBuilder.build(
            PeriodReportRequest(
                driverName: appState.catalog.profile?.name ?? "",
                scope: PeriodReportBuilder.scope(kind: kind, containing: day, week: week),
                loads: appState.catalog.loads.map(loadInput),
                fuel: appState.catalog.diesel.map {
                    PeriodReportFuelFill(totalCost: $0.totalCost, gallons: $0.gallons, date: $0.date)
                },
                expenses: appState.catalog.expenses.map {
                    PeriodReportExpense(amount: $0.amount, date: $0.date)
                },
                weeklyGoal: settings.weeklyGoal,
                generatedAt: Date(),
                language: PeriodReportLanguage.from(code: AppLocale.resolvedCode(for: settings.language)),
                measurementSystem: settings.measurementSystem,
                week: week
            )
        )
    }

    private func loadInput(_ load: Load) -> PeriodReportLoadInput {
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
            penalties: (load.penalties ?? []).map { PeriodReportPenalty(summary: $0.summary, amount: $0.amount) }
        )
    }

    private func share() {
        let current = report
        let subject = "\(current.brand) — \(current.periodTitle)"
        switch format {
        case .pdf:
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(current.fileStem).pdf")
            do {
                try PeriodReportPDF.data(for: current).write(to: url, options: .atomic)
                activity = ReportActivity(items: [PeriodReportActivityItem(file: url, subject: subject)])
            } catch {
                errorMessage = error.localizedDescription
            }
        case .text:
            activity = ReportActivity(items: [
                PeriodReportActivityItem(text: PeriodReportText.render(current), subject: subject),
            ])
        }
    }
}

private enum ShareFormat: String, CaseIterable, Identifiable {
    case pdf
    case text

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pdf: return "journal.share.pdf"
        case .text: return "journal.share.text"
        }
    }
}

private struct ReportActivity: Identifiable {
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
