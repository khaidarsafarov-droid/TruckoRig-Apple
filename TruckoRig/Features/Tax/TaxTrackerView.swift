import SwiftUI
import UIKit

/// Quarterly tax estimate: paycheck gross, diesel, and $69 per on-duty day.
struct TaxTrackerView: View {

    @Environment(AppState.self) private var appState
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var exportURL: ExportedBackup?
    @State private var isChoosingExport = false
    @State private var isExporting = false
    @State private var exportMessage: String?
    @State private var sendAll = true
    @State private var sendLoads = true
    @State private var sendDiesel = true
    @State private var sendPerDiem = true
    @State private var sendMaintenance = true

    private var calendar: Calendar { Calendar.current }
    private var reportingWeek: TruckingWeek { appState.settings.truckingWeek }

    /// French captions only when the driver is actually in French. English and Russian
    /// keep the workbook text they already get.
    private var exportLanguage: AccountantWorkbookLanguage {
        switch appState.settings.language {
        case .french:
            return .french
        case .system where Locale.preferredLanguages.first?.hasPrefix("fr") == true:
            return .french
        default:
            return .russian
        }
    }

    /// Reporting week-year, matching Android `getLoadsByWeekYearOnce`.
    private var loadsThisYear: [Load] {
        appState.catalog.loads.filter { $0.year == year }
    }

    private var dieselThisYear: [Diesel] {
        appState.catalog.diesel.filter { reportingWeek.week(for: $0.date).year == year }
    }

    private var paychecksThisYear: [Paycheck] {
        appState.catalog.paychecks.filter { $0.year == year }
    }

    private var autoDates: Set<String> {
        PerDiemCalculator.uniqueOnDutyDates(
            loads: loadsThisYear.map(\.summary),
            year: year,
            today: Date(),
            calendar: calendar
        )
    }

    private var effectiveDates: Set<String> {
        let overrides = appState.catalog.perDiemOverrides
        let snapshot = PerDiemOverrideSnapshot(
            included: Set(overrides.filter(\.included).map(\.isoDate)),
            excluded: Set(overrides.filter { !$0.included }.map(\.isoDate))
        )
        return PerDiemDayOverrides.apply(autoDates: autoDates, snapshot: snapshot)
    }

    private var estimate: TaxEstimate {
        let gross = paychecksThisYear.reduce(0) { partial, paycheck in
            let gross = paycheck.grossAmount.flatMap { $0 > 0 ? $0 : nil } ?? paycheck.amount
            return partial + gross
        }
        let diesel = dieselThisYear.reduce(0) { $0 + $1.totalCost }
        return TaxEstimate.make(
            grossIncome: gross,
            dieselDeductions: diesel,
            perDiemDays: effectiveDates.count,
            today: Date(),
            calendar: calendar
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.standard) {
                yearSelector
                if !estimate.nextQuarterLabel.isEmpty {
                    SoftCard {
                        Text("tax.nextQuarter \(estimate.nextQuarterLabel)")
                            .font(.appHeadline)
                        Text("tax.inDays \(estimate.daysUntilNextQuarter)")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                }
                SoftCard {
                    Text("tax.income").font(.appHeadline)
                    Text(Formatters.moneyPrecise(estimate.grossIncome))
                        .font(.appTitle)
                        .foregroundStyle(Color.forestPrimary)
                }
                SoftCard {
                    Text("tax.deductions").font(.appHeadline)
                    Text("tax.diesel \(Formatters.moneyPrecise(estimate.dieselDeductions))")
                    Text("tax.perDiem \(estimate.perDiemDays) \(Formatters.moneyPrecise(estimate.perDiemAmount))")
                    Text("tax.totalDeductions \(Formatters.moneyPrecise(estimate.dieselDeductions + estimate.perDiemAmount))")
                        .font(.appCaptionMedium)
                }
                .font(.appBody)
                SoftCard {
                    LabeledContent("tax.taxable") { Text(Formatters.moneyPrecise(estimate.taxableIncome)) }
                    LabeledContent("tax.se") { Text(Formatters.moneyPrecise(estimate.selfEmploymentTax)) }
                    LabeledContent("tax.federal") { Text(Formatters.moneyPrecise(estimate.federalTax)) }
                    LabeledContent("tax.owed") { Text(Formatters.moneyPrecise(estimate.totalOwed)) }
                        .font(.appHeadline)
                }
                SoftButton(title: "tax.send", systemImage: "square.and.arrow.up", isLoading: isExporting) {
                    openSendSheet()
                }
                .disabled(isExporting)
                if let exportMessage {
                    Text(exportMessage)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                Text("tax.disclaimer")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                calendarCard
            }
            .padding(Spacing.standard)
        }
        .forestBackground()
        .premiumGated("premium.locked.tax")
        .navigationTitle("screen.tax")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openSendSheet()
                } label: {
                    Label("tax.send", systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)
                .accessibilityLabel("tax.send")
            }
        }
        .sheet(isPresented: $isChoosingExport) {
            sendSheet
        }
        .sheet(item: $exportURL) { export in
            ShareSheet(items: [WorkbookShareSource(url: export.url)])
        }
    }

    private var yearSelector: some View {
        HStack {
            Button { shiftYear(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(String(year)).font(.appHeadline)
            Spacer()
            Button { shiftYear(1) } label: { Image(systemName: "chevron.right") }
        }
        .foregroundStyle(Color.forestText)
    }

    private var calendarCard: some View {
        SoftCard {
            Text("tax.calendar.title").font(.appHeadline)
            Text("tax.calendar.subtitle \(effectiveDates.count) \(Int(PerDiemCalculator.dailyRate))")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Text("tax.calendar.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            monthPager
            let days = monthDays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(days, id: \.self) { day in
                    if day == 0 {
                        Color.clear.frame(height: 32)
                    } else {
                        dayButton(day)
                    }
                }
            }
        }
    }

    private var monthPager: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle).font(.appBodyMedium)
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    private var monthTitle: String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let date = calendar.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        return formatter.string(from: date)
    }

    private func dayButton(_ day: Int) -> some View {
        let iso = String(format: "%04d-%02d-%02d", year, month, day)
        let on = effectiveDates.contains(iso)
        return Button {
            toggle(iso)
        } label: {
            Text("\(day)")
                .font(.appCaptionMedium)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    on ? AnyShapeStyle(Color.forestPrimary) : AnyShapeStyle(Color.forestSurfaceMuted),
                    in: Circle()
                )
                .foregroundStyle(on ? Color.forestOnPrimary : Color.forestText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(iso)
    }

    private func monthDays() -> [Int] {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let start = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: start)
        else { return [] }
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: 0, count: leading) + Array(range)
    }

    private func shiftYear(_ delta: Int) {
        year += delta
        if year == calendar.component(.year, from: Date()) {
            month = calendar.component(.month, from: Date())
        } else {
            month = 1
        }
    }

    private func shiftMonth(_ delta: Int) {
        month += delta
        if month < 1 {
            month = 12
            year -= 1
        } else if month > 12 {
            month = 1
            year += 1
        }
    }

    private func toggle(_ iso: String) {
        guard iso.count == 10 else { return }
        do {
            try appState.financeRepository().togglePerDiem(
                isoDate: iso,
                autoDates: autoDates,
                effectiveDates: effectiveDates
            )
        } catch {
            exportMessage = error.localizedDescription
        }
    }

    private var sendSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text("tax.send.hint \(year)")
                        .font(.appBody)
                        .foregroundStyle(Color.forestTextSecondary)
                    Text("tax.send.what")
                        .font(.appHeadline)
                        .padding(.top, Spacing.tight)
                    sendCheck("tax.send.all", checked: sendAll, enabled: !isExporting) {
                        sendAll.toggle()
                        if sendAll {
                            sendLoads = true
                            sendDiesel = true
                            sendPerDiem = true
                            sendMaintenance = true
                        }
                    }
                    sendCheck("tax.send.loads", checked: sendLoads, enabled: !isExporting && !sendAll) {
                        sendLoads.toggle()
                        syncAllFromParts()
                    }
                    sendCheck("tax.send.diesel", checked: sendDiesel, enabled: !isExporting && !sendAll) {
                        sendDiesel.toggle()
                        syncAllFromParts()
                    }
                    sendCheck("tax.send.perDiem", checked: sendPerDiem, enabled: !isExporting && !sendAll) {
                        sendPerDiem.toggle()
                        syncAllFromParts()
                    }
                    sendCheck("tax.send.maintenance", checked: sendMaintenance, enabled: !isExporting && !sendAll) {
                        sendMaintenance.toggle()
                        syncAllFromParts()
                    }
                    Text("tax.send.apps")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                        .padding(.top, Spacing.standard)
                    SoftButton(
                        title: isExporting ? LocalizedStringKey("tax.send.preparing") : LocalizedStringKey("tax.send.action"),
                        isLoading: isExporting
                    ) {
                        share(sections: sendSelection)
                    }
                    .disabled(!canSend || isExporting)
                    if let exportMessage {
                        Text(exportMessage)
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                }
                .padding(Spacing.standard)
            }
            .forestBackground()
            .navigationTitle("tax.send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { isChoosingExport = false }
                        .disabled(isExporting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var sendSelection: Set<AccountantExportSection> {
        if sendAll { return [.all] }
        var sections = Set<AccountantExportSection>()
        if sendLoads { sections.insert(.loads) }
        if sendDiesel { sections.insert(.diesel) }
        if sendPerDiem { sections.insert(.perDiem) }
        if sendMaintenance { sections.insert(.maintenance) }
        return sections
    }

    private var canSend: Bool {
        sendAll || !sendSelection.isEmpty
    }

    private func sendCheck(
        _ title: LocalizedStringKey,
        checked: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.tight) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(enabled ? Color.forestPrimary : Color.forestTextSecondary)
                Text(title)
                    .font(.appBody)
                    .foregroundStyle(enabled ? Color.forestText : Color.forestTextSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func syncAllFromParts() {
        sendAll = sendLoads && sendDiesel && sendPerDiem && sendMaintenance
    }

    private func openSendSheet() {
        sendAll = true
        sendLoads = true
        sendDiesel = true
        sendPerDiem = true
        sendMaintenance = true
        exportMessage = nil
        isChoosingExport = true
    }

    private func share(sections: Set<AccountantExportSection>) {
        isExporting = true
        let input = workbookInput()
        guard !AccountantWorkbook.isEmpty(input, sections: sections) else {
            isExporting = false
            exportMessage = String(localized: "tax.send.empty")
            return
        }
        let bytes = AccountantWorkbook.data(
            input: input,
            sections: sections,
            language: exportLanguage,
            units: appState.settings.measurementSystem
        )
        let name = AccountantWorkbook.fileName(year: year, sections: sections, calendar: calendar)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try bytes.write(to: url, options: .atomic)
            exportMessage = String(localized: "tax.export.success \(name)")
            isExporting = false
            isChoosingExport = false
            DispatchQueue.main.async {
                exportURL = ExportedBackup(url: url)
            }
        } catch {
            isExporting = false
            exportMessage = String(localized: "tax.export.error \(error.localizedDescription)")
        }
    }

    private func workbookInput() -> AccountantWorkbookInput {
        let prefix = String(format: "%04d-", year)
        let maintenance = appState.catalog.maintenanceArchive
            .filter { $0.serviceDate.hasPrefix(prefix) }
            .sorted { $0.serviceDate < $1.serviceDate }
            .map { entry in
                AccountantWorkbookMaintenance(
                    serviceDate: entry.serviceDate,
                    serviceName: entry.serviceName,
                    description: entry.description,
                    amount: entry.amount
                )
            }
        return AccountantWorkbookInput(
            year: year,
            loads: loadsThisYear.map(workbookLoad),
            diesel: dieselThisYear.map(workbookDiesel),
            perDiemDates: effectiveDates,
            maintenance: maintenance,
            grossIncome: estimate.grossIncome
        )
    }

    private func workbookLoad(_ load: Load) -> AccountantWorkbookLoad {
        var summary = load.summary
        if summary.firstPickupAt == nil {
            summary.firstPickupAt = load.date
        }
        if summary.actualFinishAt == nil && summary.lastDeliveryAt == nil {
            summary.lastDeliveryAt = load.date
        }
        let days = PerDiemCalculator.uniqueOnDutyDates(
            loads: [summary],
            year: year,
            today: Date(),
            calendar: calendar
        ).count
        let route = load.route.isEmpty ? "\(load.pointA ?? "") → \(load.pointB ?? "")" : load.route
        return AccountantWorkbookLoad(
            date: DateUtils.isoDay(load.date),
            tripId: load.tripId,
            route: route,
            rate: MoneyCents.fromDollars(load.totalRate),
            miles: load.totalMiles,
            onDutyDays: days
        )
    }

    private func workbookDiesel(_ fill: Diesel) -> AccountantWorkbookDiesel {
        let ref = reportingWeek.week(for: fill.date)
        let start = reportingWeek.startDate(of: ref).map { DateUtils.isoDay($0) } ?? ""
        let end = reportingWeek.endDate(of: ref).map { DateUtils.isoDay($0) } ?? ""
        return AccountantWorkbookDiesel(
            weekNumber: ref.weekNumber,
            year: ref.year,
            weekStartDate: start,
            weekEndDate: end,
            totalAmount: MoneyCents.fromDollars(fill.totalCost),
            gallons: fill.gallons,
            pricePerGallon: fill.pricePerGallon > 0 ? fill.pricePerGallon : nil,
            discountPricePerGallon: fill.discountPricePerGallon.flatMap { $0 > 0 ? $0 : nil },
            location: fill.location ?? ""
        )
    }
}

/// Share item that sets the mail subject to the workbook name, matching Android `EXTRA_SUBJECT`.
final class WorkbookShareSource: NSObject, UIActivityItemSource {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        url.deletingPathExtension().lastPathComponent
    }
}
