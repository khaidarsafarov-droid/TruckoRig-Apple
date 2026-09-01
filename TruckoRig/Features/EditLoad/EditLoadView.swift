import SwiftData
import SwiftUI

/// Sheet for editing an existing trip: fields, stops, penalties and the dispute state.
struct EditLoadView: View {

    let load: Load

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draft: LoadDraft
    @State private var editingStop: StopEditTarget?
    @State private var hasFinishOverride: Bool
    @State private var finishDate: Date
    @State private var errorMessage: String?
    @State private var isAddingPenalty = false

    init(load: Load) {
        self.load = load
        let draft = LoadDraft(load: load)
        _draft = State(initialValue: draft)
        _hasFinishOverride = State(initialValue: draft.actualFinishDate != nil)
        _finishDate = State(initialValue: draft.actualFinishDate ?? load.lastDeliveryAt ?? load.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                LoadFormFields(draft: $draft)

                Section("load.finish") {
                    Toggle("load.finish.override", isOn: $hasFinishOverride)
                    if hasFinishOverride {
                        DatePicker("load.finish.date", selection: $finishDate)
                    }
                    Text("load.finish.hint")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }

                StopsSection(
                    stops: $draft.stops,
                    onEdit: { editingStop = StopEditTarget(index: $0) },
                    onAdd: { draft.stops.append(StopDraft(type: $0, stopNumber: draft.stops.count + 1)) },
                    onDelete: { draft.stops.remove(atOffsets: $0) },
                    onMove: { draft.stops.move(fromOffsets: $0, toOffset: $1) }
                )

                disputeSection
                penaltiesSection
            }
            .navigationTitle("load.edit")
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
                StopEditorView(stop: $draft.stops[target.index])
            }
            .sheet(isPresented: $isAddingPenalty) {
                PenaltyEditorView { summary, amount, date in
                    addPenalty(summary: summary, amount: amount, date: date)
                }
            }
            .alert(
                "error.title",
                isPresented: .constant(errorMessage != nil),
                actions: { Button("action.ok") { errorMessage = nil } },
                message: { Text(errorMessage ?? "") }
            )
        }
    }

    private var disputeSection: some View {
        Section("load.dispute") {
            Toggle("load.dispute.open", isOn: $draft.isDispute)
            if draft.isDispute {
                Toggle("load.dispute.completed", isOn: $draft.disputeCompleted)
                SoftNumberField(title: "load.dispute.amount", value: disputeAmountBinding)
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
        LoadRepository(context: modelContext, sync: appState.sync, week: appState.settings.truckingWeek)
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("penalty.summary", text: $summary)
                SoftNumberField(title: "penalty.amount", value: $amount)
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
        .presentationDetents([.medium])
    }
}
