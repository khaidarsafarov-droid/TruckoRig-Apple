import SwiftData
import SwiftUI

/// Fuel purchases with running cost and fuel economy.
struct DieselListView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Diesel.date, order: .reverse) private var fills: [Diesel]

    @State private var editing: Diesel?
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var totalCost: Double { fills.reduce(0) { $0 + $1.totalCost } }
    private var totalGallons: Double { fills.reduce(0) { $0 + $1.gallons } }

    private var mpg: Double {
        AnalyticsCalculator.milesPerGallon(
            odometers: fills.compactMap { fill in
                fill.odometer.map { (odometer: $0, gallons: fill.gallons) }
            }
        )
    }

    var body: some View {
        List {
            if !fills.isEmpty {
                Section {
                    HStack {
                        StatTile(title: "diesel.totalCost", value: Formatters.money(totalCost))
                        StatTile(title: "diesel.totalGallons", value: Formatters.gallons(totalGallons))
                        StatTile(title: "diesel.mpg", value: Formatters.mpg(mpg))
                    }
                    if mpg == 0 {
                        Text("diesel.mpg.hint")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                }
                .listRowBackground(Color.forestCard)
            }

            ForEach(fills) { fill in
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

            if fills.isEmpty {
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
                Text("\(DateUtils.mediumDate(fill.date)) · \(Formatters.gallons(fill.gallons))" as String)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Formatters.moneyPrecise(fill.totalCost))
                    .font(.appCaptionMedium)
                Text(fill.pricePerGallon.formatted(.currency(code: Formatters.currencyCode).precision(.fractionLength(3))))
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func delete(_ fill: Diesel) {
        let repository = appState.financeRepository(in: modelContext)
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var gallons: Double
    @State private var totalCost: Double
    @State private var pricePerGallon: Double
    @State private var location: String
    @State private var state: String
    @State private var date: Date
    @State private var odometerText: String
    @State private var errorMessage: String?

    init(fill: Diesel?) {
        self.fill = fill
        _gallons = State(initialValue: fill?.gallons ?? 0)
        _totalCost = State(initialValue: fill?.totalCost ?? 0)
        _pricePerGallon = State(initialValue: fill?.pricePerGallon ?? 0)
        _location = State(initialValue: fill?.location ?? "")
        _state = State(initialValue: fill?.state ?? "")
        _date = State(initialValue: fill?.date ?? Date())
        _odometerText = State(initialValue: fill?.odometer.map(String.init) ?? "")
    }

    private var derivedPrice: Double {
        pricePerGallon > 0 ? pricePerGallon : (gallons > 0 ? totalCost / gallons : 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("diesel.amounts") {
                    SoftNumberField(title: "diesel.gallons", value: $gallons)
                    SoftNumberField(title: "diesel.totalCost", value: $totalCost)
                    SoftNumberField(title: "diesel.pricePerGallon", value: $pricePerGallon)
                    LabeledContent("diesel.pricePerGallon.derived") {
                        Text(derivedPrice.formatted(.currency(code: Formatters.currencyCode).precision(.fractionLength(3))))
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(gallons <= 0 || totalCost <= 0)
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
        let repository = appState.financeRepository(in: modelContext)
        let odometer = Int(odometerText.filter(\.isNumber))
        let normalizedState = state.trimmed.isEmpty ? nil : USStates.normalize(state)
        do {
            if let fill {
                try repository.update(
                    fill,
                    gallons: gallons,
                    totalCost: totalCost,
                    pricePerGallon: pricePerGallon,
                    location: location,
                    state: normalizedState,
                    date: date,
                    odometer: odometer
                )
            } else {
                try repository.addDiesel(
                    gallons: gallons,
                    totalCost: totalCost,
                    pricePerGallon: pricePerGallon,
                    location: location,
                    state: normalizedState,
                    date: date,
                    odometer: odometer
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
