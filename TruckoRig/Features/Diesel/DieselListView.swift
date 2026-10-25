import SwiftUI
import UIKit

/// Fuel purchases with running cost and fuel economy.
struct DieselListView: View {

    @Environment(AppState.self) private var appState

    private var fills: [Diesel] { appState.catalog.diesel }

    @State private var editing: Diesel?
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var scope: DieselScope = .all

    private enum DieselScope: String, CaseIterable, Identifiable {
        case all
        case thisWeek
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .all: return "diesel.scope.all"
            case .thisWeek: return "diesel.scope.week"
            }
        }
    }

    private var visibleFills: [Diesel] {
        guard scope == .thisWeek else { return fills }
        let week = appState.settings.truckingWeek
        let current = week.currentWeek()
        let rows = fills.map { DieselJournalRow(id: $0.id.uuidString, recordedAt: $0.date, sourceFileName: $0.sourceFileName) }
        let kept = Set(DieselJournalFilter.forWeek(rows, weekNumber: current.weekNumber, year: current.year, week: week).map(\.id))
        return fills.filter { kept.contains($0.id.uuidString) }
    }

    private var totalCost: Double { visibleFills.reduce(0) { $0 + $1.totalCost } }
    private var totalGallons: Double { visibleFills.reduce(0) { $0 + $1.gallons } }

    private var mpg: Double {
        AnalyticsCalculator.milesPerGallon(
            odometers: visibleFills.compactMap { fill in
                fill.odometer.map { (odometer: $0, gallons: fill.gallons) }
            }
        )
    }

    var body: some View {
        let system = appState.settings.measurementSystem
        List {
            if !fills.isEmpty {
                Section {
                    Picker("diesel.scope", selection: $scope) {
                        ForEach(DieselScope.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        StatTile(title: "diesel.totalCost", value: Formatters.money(totalCost))
                        StatTile(
                            title: system == .kilometers ? "diesel.totalLiters" : "diesel.totalGallons",
                            value: Formatters.gallons(totalGallons, system: system)
                        )
                        StatTile(title: "diesel.mpg", value: Formatters.mpg(mpg, system: system))
                    }
                    if mpg == 0 {
                        Text(system == .kilometers ? "diesel.mpg.hint.metric" : "diesel.mpg.hint")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                }
                .listRowBackground(Color.forestCard)
            }

            ForEach(visibleFills) { fill in
                Button { editing = fill } label: {
                    row(fill)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.forestCard)
                .swipeActions {
                    Button(role: .destructive) { delete(fill) } label: {
                        Label("action.delete", systemImage: "trash")
                    }
                }
            }

            if visibleFills.isEmpty {
                EmptyStateView(
                    systemImage: "fuelpump",
                    title: "diesel.empty.title",
                    message: "diesel.empty.message",
                    actionTitle: "diesel.add",
                    action: { isAdding = true }
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle("screen.diesel")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: {
                    Label("diesel.add", systemImage: "plus")
                }
                .accessibilityLabel("diesel.add")
            }
        }
        .sheet(isPresented: $isAdding) { DieselEditorView(fill: nil) }
        .sheet(item: $editing) { fill in DieselEditorView(fill: fill) }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private func row(_ fill: Diesel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(fill.location ?? String(localized: "diesel.untitled"))
                    .font(.appBodyMedium)
                    .foregroundStyle(Color.forestText)
                Text("\(DateUtils.mediumDate(fill.date)) · \(Formatters.gallons(fill.gallons, system: appState.settings.measurementSystem))" as String)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.moneyPrecise(fill.totalCost))
                    .font(.appCaptionMedium)
                Text(Formatters.unitPrice(fill.pricePerGallon, system: appState.settings.measurementSystem))
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                if let saved = DieselPurchaseMath.savings(
                    gallons: fill.gallons,
                    pricePerGallon: fill.pricePerGallon,
                    discountPricePerGallon: fill.discountPricePerGallon
                ), saved > 0 {
                    Text("diesel.saved \(Formatters.moneyPrecise(saved))")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestSuccess)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func delete(_ fill: Diesel) {
        let repository = appState.financeRepository()
        do {
            try repository.delete(fill)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Add or edit one fill-up. Price per gallon is derived when the driver leaves it blank.
struct DieselEditorView: View {

    let fill: Diesel?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var gallons: Double
    @State private var totalCost: Double
    @State private var pricePerGallon: Double
    @State private var discountPrice: Double
    @State private var location: String
    @State private var state: String
    @State private var date: Date
    @State private var odometerText: String
    @State private var rawText: String?
    @State private var receiptFileName: String?
    @State private var sourceFileName: String?
    @State private var pendingImage: UIImage?
    @State private var scanMessage: String?
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var didPresentOdometer = false

    private var system: MeasurementSystem { appState.settings.measurementSystem }

    init(fill: Diesel?) {
        self.fill = fill
        _gallons = State(initialValue: fill?.gallons ?? 0)
        _totalCost = State(initialValue: fill?.totalCost ?? 0)
        _pricePerGallon = State(initialValue: fill?.pricePerGallon ?? 0)
        _discountPrice = State(initialValue: fill?.discountPricePerGallon ?? 0)
        _location = State(initialValue: fill?.location ?? "")
        _state = State(initialValue: fill?.state ?? "")
        _date = State(initialValue: fill?.date ?? Date())
        _odometerText = State(initialValue: fill?.odometer.map(String.init) ?? "")
        _rawText = State(initialValue: fill?.rawText)
        _receiptFileName = State(initialValue: fill?.receiptFileName)
        _sourceFileName = State(initialValue: fill?.sourceFileName)
    }

    private var derivedPrice: Double {
        pricePerGallon > 0 ? pricePerGallon : (gallons > 0 ? totalCost / gallons : 0)
    }

    private var paidTotal: Double? {
        DieselPurchaseMath.paidTotal(
            gallons: gallons > 0 ? gallons : nil,
            pricePerGallon: pricePerGallon > 0 ? pricePerGallon : nil,
            discountPricePerGallon: discountPrice > 0 ? discountPrice : nil
        )
    }

    private var savings: Double? {
        DieselPurchaseMath.savings(
            gallons: gallons > 0 ? gallons : nil,
            pricePerGallon: pricePerGallon > 0 ? pricePerGallon : nil,
            discountPricePerGallon: discountPrice > 0 ? discountPrice : nil
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("diesel.receipt") {
                    Text(system == .kilometers ? "diesel.scan.hint.metric" : "diesel.scan.hint")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    ReceiptCaptureButtons { image in
                        Task { await recognize(image) }
                    }
                    if isScanning {
                        ProgressView("diesel.scanning")
                    }
                    if let scanMessage {
                        Text(scanMessage)
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                }
                Section("diesel.amounts") {
                    SoftNumberField(
                        title: system == .kilometers ? "diesel.liters" : "diesel.gallons",
                        value: UnitEntry.volume(stored: $gallons, system: system)
                    )
                    SoftNumberField(
                        title: system == .kilometers ? "diesel.pricePerLiter" : "diesel.pricePerGallon",
                        value: UnitEntry.unitPrice(stored: $pricePerGallon, system: system)
                    )
                    SoftNumberField(
                        title: "diesel.discount",
                        value: UnitEntry.unitPrice(stored: $discountPrice, system: system)
                    )
                    SoftNumberField(title: "diesel.totalCost", value: $totalCost)
                    if let paidTotal {
                        LabeledContent("diesel.paid") {
                            Text(Formatters.moneyPrecise(paidTotal))
                        }
                    }
                    if let savings, savings > 0 {
                        LabeledContent("diesel.saved.label") {
                            Text(Formatters.moneyPrecise(savings))
                                .foregroundStyle(Color.forestSuccess)
                        }
                    }
                    LabeledContent("diesel.pricePerGallon.derived") {
                        Text(Formatters.unitPrice(derivedPrice, system: system))
                    }
                }

                Section("diesel.where") {
                    SoftTextField(title: "diesel.location", text: $location)
                    SoftTextField(title: "stop.state", text: $state, autocapitalization: .characters)
                    DatePicker("diesel.date", selection: $date, displayedComponents: .date)
                    SoftTextField(title: "diesel.odometer", text: $odometerText, keyboard: .numberPad)
                }
            }
            .navigationTitle(fill == nil ? "diesel.add" : "diesel.edit")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: presentOdometer)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(gallons <= 0 || (pricePerGallon <= 0 && totalCost <= 0))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .alert(
                "error.title",
                isPresented: .isPresented($errorMessage),
                actions: { Button("action.ok") {} },
                message: { Text(errorMessage ?? "") }
            )
        }
    }

    private func save() {
        let discountText = discountPrice > 0 ? DieselReceiptExtractor.formatField(discountPrice) : ""
        let priceText = pricePerGallon > 0 ? DieselReceiptExtractor.formatField(pricePerGallon) : ""
        if let failure = DieselFormValidation.validate(
            gallonsText: gallons > 0 ? DieselReceiptExtractor.formatField(gallons) : "",
            priceText: priceText,
            discountText: discountText
        ) {
            errorMessage = String(localized: message(for: failure))
            return
        }
        let repository = appState.financeRepository()
        let odometer = commitOdometer()
        let normalizedState = state.trimmed.isEmpty ? nil : USStates.normalize(state)
        let paid = paidTotal ?? totalCost
        let fileName = storedReceipt()
        do {
            if let fill {
                try repository.update(
                    fill,
                    gallons: gallons,
                    totalCost: paid,
                    pricePerGallon: pricePerGallon,
                    location: location,
                    state: normalizedState,
                    date: date,
                    odometer: odometer,
                    discountPricePerGallon: discountPrice > 0 ? discountPrice : nil,
                    rawText: rawText,
                    receiptFileName: fileName,
                    sourceFileName: sourceFileName
                )
            } else {
                try repository.addDiesel(
                    gallons: gallons,
                    totalCost: paid,
                    pricePerGallon: pricePerGallon,
                    location: location,
                    state: normalizedState,
                    date: date,
                    odometer: odometer,
                    discountPricePerGallon: discountPrice > 0 ? discountPrice : nil,
                    rawText: rawText,
                    receiptFileName: fileName,
                    sourceFileName: sourceFileName
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recognize(_ image: UIImage) async {
        isScanning = true
        scanMessage = nil
        pendingImage = image
        let recognition = await OCRService.recognizeText(in: image)
        isScanning = false
        guard let text = recognition?.text, !text.isEmpty else {
            scanMessage = String(localized: "diesel.scan.failed")
            return
        }
        rawText = text
        guard let parsed = DieselTextParser.parse(text) else {
            scanMessage = String(localized: "diesel.scan.none")
            return
        }
        if let gallons = parsed.gallons { self.gallons = gallons }
        if let price = parsed.pricePerGallon { pricePerGallon = price }
        if let discount = parsed.discountPricePerGallon { discountPrice = discount }
        totalCost = parsed.totalAmount
        if let location = parsed.location { self.location = location }
        if let iso = parsed.date { date = dateFromISO(iso) ?? date }
        sourceFileName = "receipt-\(UUID().uuidString.prefix(8)).jpg"
        let summary = [
            parsed.gallons.map { Formatters.gallons($0, system: system) },
            parsed.pricePerGallon.map { Formatters.unitPrice($0, system: system) },
        ].compactMap { $0 }.joined(separator: ", ")
        scanMessage = String(localized: "diesel.scan.found \(summary)")
    }

    private func storedReceipt() -> String? {
        if let pendingImage {
            return try? MediaStore(scope: appState.persistence.scope).saveJPEG(pendingImage)
        }
        return receiptFileName
    }

    private func presentOdometer() {
        guard !didPresentOdometer else { return }
        didPresentOdometer = true
        guard let miles = fill?.odometer else { return }
        let shown = Int(MeasurementUnits.displayDistance(Double(miles), system: system).rounded())
        odometerText = String(shown)
    }

    /// Whole miles in storage. An unedited reading of the original odometer is kept.
    private func commitOdometer() -> Int? {
        let digits = odometerText.filter(\.isNumber)
        guard let entered = Int(digits) else { return nil }
        if let original = fill?.odometer {
            let shown = Int(MeasurementUnits.displayDistance(Double(original), system: system).rounded())
            if shown == entered { return original }
        }
        return Int(MeasurementUnits.storageDistance(Double(entered), system: system).rounded())
    }

    private func message(for failure: DieselFormError) -> String.LocalizationValue {
        switch failure {
        case .gallons:
            return system == .kilometers ? "diesel.error.liters" : "diesel.error.gallons"
        case .price:
            return system == .kilometers ? "diesel.error.pricePerLiter" : "diesel.error.price"
        case .discountInvalid: return "diesel.error.discount"
        case .discountAbovePrice: return "diesel.error.discountHigh"
        case .amount: return "diesel.error.amount"
        }
    }

    private func dateFromISO(_ iso: String) -> Date? {
        let pieces = iso.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var components = DateComponents()
        components.year = pieces[0]
        components.month = pieces[1]
        components.day = pieces[2]
        return Calendar.current.date(from: components)
    }
}
