import SwiftUI

/// Which part of the editor a detail-screen chip opens. `nil` is the full form.
enum LoadEditorFocus: Identifiable {
    case miles
    case deadhead
    case finish
    case dispute

    var id: Self { self }
}

/// Sheet for editing an existing trip: fields, stops, penalties and the dispute state.
struct EditLoadView: View {

    let load: Load
    var focus: LoadEditorFocus?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: LoadDraft
    @State private var editingStop: StopEditTarget?
    @State private var hasFinishOverride: Bool
    @State private var finishDate: Date
    @State private var errorMessage: String?
    @State private var isAddingPenalty = false
    @State private var detent: PresentationDetent

    init(load: Load, focus: LoadEditorFocus? = nil) {
        self.load = load
        self.focus = focus
        var draft = LoadDraft(load: load)
        if focus == .dispute, !draft.isDispute {
            draft.isDispute = true
        }
        _draft = State(initialValue: draft)
        _hasFinishOverride = State(initialValue: focus == .finish || draft.actualFinishDate != nil)
        _finishDate = State(initialValue: draft.actualFinishDate ?? load.lastDeliveryAt ?? Date())
        _detent = State(initialValue: focus == nil ? .large : .medium)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch focus {
                case .miles:
                    milesSection
                case .deadhead:
                    deadheadSection
                case .finish:
                    finishSection
                case .dispute:
                    disputeSection
                case nil:
                    LoadFormFields(draft: $draft)
                    LoadExtraFields(draft: $draft)
                    finishSection
                    StopsSection(
                        stops: $draft.stops,
                        onEdit: { editingStop = StopEditTarget(index: $0) },
                        onAdd: { draft.stops.append(StopDraft(type: $0, stopNumber: draft.stops.count + 1)) },
                        onDelete: {
                            editingStop = nil
                            draft.stops.remove(atOffsets: $0)
                            draft.renumberStops()
                        },
                        onMove: {
                            editingStop = nil
                            draft.stops.move(fromOffsets: $0, toOffset: $1)
                            draft.renumberStops()
                        }
                    )
                    disputeSection
                    penaltiesSection
                }
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(!draft.isValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .sheet(item: $editingStop) { target in
                if draft.stops.indices.contains(target.index) {
                    StopEditorView(stop: $draft.stops[target.index])
                }
            }
            .sheet(isPresented: $isAddingPenalty) {
                PenaltyEditorView { summary, amount, date in
                    addPenalty(summary: summary, amount: amount, date: date)
                }
            }
            .alert(
                "error.title",
                isPresented: .isPresented($errorMessage),
                actions: { Button("action.ok") {} },
                message: { Text(errorMessage ?? "") }
            )
        }
        .presentationDetents(focus == nil ? [.large] : [.medium, .large], selection: $detent)
    }

    private var titleKey: LocalizedStringKey {
        switch focus {
        case .miles:
            return appState.settings.measurementSystem == .kilometers ? "load.totalKilometers" : "load.totalMiles"
        case .deadhead:
            return "load.deadhead"
        case .finish:
            return "load.chip.finish.add"
        case .dispute:
            return "load.dispute"
        case nil:
            return "load.edit"
        }
    }

    private var milesSection: some View {
        Section {
            SoftNumberField(
                title: appState.settings.measurementSystem == .kilometers ? "load.totalKilometers" : "load.totalMiles",
                value: UnitEntry.distance(stored: $draft.totalMiles, system: appState.settings.measurementSystem)
            )
            Text("load.chip.miles.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private var deadheadSection: some View {
        Section {
            SoftNumberField(
                title: "load.deadhead",
                value: UnitEntry.distance(stored: $draft.deadheadMiles, system: appState.settings.measurementSystem)
            )
            Text("load.deadhead.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private var finishSection: some View {
        Section("load.finish") {
            Toggle("load.finish.override", isOn: $hasFinishOverride)
            if hasFinishOverride {
                DatePicker("load.finish.date", selection: $finishDate)
            }
            Text("load.finish.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private var disputeSection: some View {
        Section("load.dispute") {
            Toggle("load.dispute.open", isOn: $draft.isDispute)
            if draft.isDispute {
                Toggle("load.dispute.completed", isOn: $draft.disputeCompleted)
                Toggle("load.dispute.apply", isOn: $draft.disputeApplyToLoad)
                SoftNumberField(title: "load.dispute.amount", value: disputeAmountBinding, money: true)
                DatePicker("load.dispute.responseDate", selection: disputeDateBinding, displayedComponents: .date)
            }
        }
    }

    private var penaltiesSection: some View {
        Section("load.penalties") {
            ForEach(load.penalties ?? []) { penalty in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(penalty.summary)
                            .font(.appBody)
                        Text(DateUtils.shortDay(penalty.date))
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                    Spacer()
                    Text(Formatters.moneyPrecise(-penalty.amount))
                        .font(.appCaptionMedium)
                        .foregroundStyle(Color.forestError)
                }
                .swipeActions {
                    Button(role: .destructive) { remove(penalty) } label: {
                        Label("action.delete", systemImage: "trash")
                    }
                }
            }
            Button {
                isAddingPenalty = true
            } label: {
                Label("load.penalties.add", systemImage: "plus.circle")
            }
            .font(.appCaptionMedium)
        }
    }

    private var disputeAmountBinding: Binding<Double> {
        Binding(get: { draft.disputeAmount ?? 0 }, set: { draft.disputeAmount = $0 > 0 ? $0 : nil })
    }

    private var disputeDateBinding: Binding<Date> {
        Binding(get: { draft.disputeResponseDate ?? Date() }, set: { draft.disputeResponseDate = $0 })
    }

    private var repository: LoadRepository {
        appState.loadRepository()
    }

    private func save() {
        draft.actualFinishDate = hasFinishOverride ? finishDate : nil
        do {
            try repository.update(load, with: draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addPenalty(summary: String, amount: Double, date: Date) {
        do {
            try repository.addPenalty(to: load, summary: summary, amount: amount, date: date)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ penalty: Penalty) {
        do {
            try repository.remove(penalty)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Small sheet for entering one penalty.
struct PenaltyEditorView: View {
    let onSave: (String, Double, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""
    @State private var amount: Double = 0
    @State private var date = Date()
    @State private var detent: PresentationDetent = .medium
    @FocusState private var focus: String?

    private var focusBinding: Binding<String?> {
        Binding(get: { focus }, set: { focus = $0 })
    }

    var body: some View {
        NavigationStack {
            FocusedForm(focus: $focus) {
                TextField("penalty.summary", text: $summary)
                    .focused($focus, equals: KeyboardField.penaltySummary)
                    .id(KeyboardField.penaltySummary)
                SoftNumberField(title: "penalty.amount", value: $amount, money: true)
                    .keyboardFocus(KeyboardField.penaltyAmount, in: focusBinding)
                DatePicker("penalty.date", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("load.penalties.add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        onSave(summary.trimmed, amount, date)
                        dismiss()
                    }
                    .disabled(summary.trimmed.isEmpty || amount <= 0)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .onChange(of: focus) { _, newValue in
            detent = KeyboardSheetDetent.resolved(resting: .medium, fieldFocused: newValue != nil)
        }
    }
}
