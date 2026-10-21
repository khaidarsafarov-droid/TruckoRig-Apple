import SwiftUI

/// Quarterly tax estimate: paycheck gross, diesel, and $69 per on-duty day.
struct TaxTrackerView: View {

    @Environment(AppState.self) private var appState
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var month = Calendar.current.component(.month, from: Date())
    @State private var exportURL: ExportedBackup?
    @State private var isChoosingExport = false
    @State private var statusMessage: String?

    private var calendar: Calendar { Calendar.current }

    private var loadsThisYear: [Load] {
        appState.catalog.loads.filter { calendar.component(.year, from: $0.date) == year }
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
        let gross = appState.catalog.paychecks
            .filter { calendar.component(.year, from: $0.date) == year }
            .reduce(0) { partial, paycheck in
                let gross = paycheck.grossAmount.flatMap { $0 > 0 ? $0 : nil } ?? paycheck.amount
                return partial + gross
            }
        let diesel = appState.catalog.diesel
            .filter { calendar.component(.year, from: $0.date) == year }
            .reduce(0) { $0 + $1.totalCost }
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
                Text("tax.disclaimer")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                calendarCard
            }
            .padding(Spacing.standard)
        }
        .forestBackground()
        .navigationTitle("screen.tax")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isChoosingExport = true
                } label: {
                    Label("tax.send", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("tax.send")
            }
        }
        .confirmationDialog("tax.send", isPresented: $isChoosingExport, titleVisibility: .visible) {
            Button("tax.send.all") { share(sections: [.all]) }
            Button("tax.send.loads") { share(sections: [.loads]) }
            Button("tax.send.diesel") { share(sections: [.diesel]) }
            Button("tax.send.perDiem") { share(sections: [.perDiem]) }
            Button("tax.send.maintenance") { share(sections: [.maintenance]) }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("tax.send.hint \(year)")
        }
        .sheet(item: $exportURL) { export in
            ShareSheet(items: [export.url])
        }
        .alert(
            "tax.exportReady",
            isPresented: .isPresented($statusMessage),
            actions: { Button("action.ok") {} },
            message: { Text(statusMessage ?? "") }
        )
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
                .background(on ? Color.forestPrimary : Color.forestSurfaceMuted, in: Circle())
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
            statusMessage = error.localizedDescription
        }
    }

    private func share(sections: Set<AccountantExportSection>) {
        let resolved = AccountantExportSection.resolve(sections)
        var rows: [AccountantExport.Row] = []
        if resolved.contains(.loads) {
            rows += loadsThisYear.map { load in
                AccountantExport.Row(section: "loads", cells: [load.tripId, Formatters.moneyPrecise(load.totalRate), DateUtils.mediumDate(load.date), load.route])
            }
        }
        if resolved.contains(.diesel) {
            rows += appState.catalog.diesel.filter { calendar.component(.year, from: $0.date) == year }.map { fill in
                AccountantExport.Row(section: "diesel", cells: [DateUtils.mediumDate(fill.date), fill.location ?? "", Formatters.moneyPrecise(fill.totalCost), Formatters.gallons(fill.gallons)])
            }
        }
        if resolved.contains(.perDiem) {
            rows += effectiveDates.sorted().map { iso in
                AccountantExport.Row(section: "per_diem", cells: [iso, String(format: "%.2f", PerDiemCalculator.dailyRate), "", ""])
            }
        }
        if resolved.contains(.maintenance) {
            let prefix = String(format: "%04d", year)
            rows += appState.catalog.maintenanceArchive.filter { $0.serviceDate.hasPrefix(prefix) }.map { entry in
                let name = entry.serviceName.isEmpty ? entry.description : entry.serviceName
                AccountantExport.Row(
                    section: "maintenance",
                    cells: [name, Formatters.moneyPrecise(entry.amount.dollars), entry.description, entry.serviceDate]
                )
            }
        }
        let counts: [AccountantExportSection: Int] = [
            .loads: rows.filter { $0.section == "loads" }.count,
            .diesel: rows.filter { $0.section == "diesel" }.count,
            .perDiem: rows.filter { $0.section == "per_diem" }.count,
            .maintenance: rows.filter { $0.section == "maintenance" }.count,
        ]
        guard !AccountantExport.isEmpty(sections: sections, counts: counts) else {
            statusMessage = String(localized: "tax.send.empty")
            return
        }
        let csv = AccountantExport.csv(year: year, rows: rows)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("truckorig-tax-\(year).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = ExportedBackup(url: url)
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
