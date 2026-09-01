import SwiftData
import SwiftUI

/// Sheet for adding a trip, either by pasting Relay text or by typing it in.
struct AddLoadView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = AddLoadViewModel()
    @State private var editingStop: StopEditTarget?

    var body: some View {
        @Bindable var model = viewModel

        NavigationStack {
            Form {
                Section {
                    RelayTextInputView(
                        text: $model.relayText,
                        parseMessage: viewModel.parseMessage,
                        errorMessage: viewModel.errorMessage,
                        onParse: { viewModel.parseRelayText() },
                        onClear: { viewModel.clearRelayText() }
                    )
                }

                LoadFormFields(draft: $model.draft)

                StopsSection(
                    stops: $model.draft.stops,
                    onEdit: { editingStop = StopEditTarget(index: $0) },
                    onAdd: { viewModel.addStop($0) },
                    onDelete: {
                        editingStop = nil
                        viewModel.removeStops(at: $0)
                    },
                    onMove: {
                        editingStop = nil
                        viewModel.moveStops(from: $0, to: $1)
                    }
                )

                if !viewModel.draft.isValid, !viewModel.draft.tripId.isEmpty {
                    Section {
                        ForEach(viewModel.draft.validationErrors, id: \.self) { error in
                            Label(error.localizedMessage, systemImage: "exclamationmark.circle")
                                .font(.appCaption)
                                .foregroundStyle(Color.forestError)
                        }
                    }
                }
            }
            .navigationTitle("journal.addLoad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(!viewModel.canSave)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .sheet(item: $editingStop) { target in
                if model.draft.stops.indices.contains(target.index) {
                    StopEditorView(stop: $model.draft.stops[target.index])
                }
            }
            .alert(
                "load.duplicate.title",
                isPresented: .isPresented($model.duplicateTripId),
                actions: { Button("action.ok") {} },
                message: { Text("load.duplicate.message \(viewModel.duplicateTripId ?? "")") }
            )
            .loadingOverlay(viewModel.isSaving, message: "status.saving")
        }
    }

    private func save() {
        let repository = appState.loadRepository(in: modelContext)
        if viewModel.save(using: repository) {
            dismiss()
        }
    }
}

/// Trip ID, money and date fields shared by add and edit.
struct LoadFormFields: View {
    @Binding var draft: LoadDraft

    var body: some View {
        Section("load.details") {
            SoftTextField(
                title: "load.tripId",
                text: $draft.tripId,
                placeholder: "T-116KYL6KW",
                autocapitalization: .characters
            )
            SoftNumberField(title: "load.totalRate", value: $draft.totalRate)
            SoftNumberField(title: "load.totalMiles", value: $draft.totalMiles)
            DatePicker("load.date", selection: $draft.date, displayedComponents: .date)

            LabeledContent("stat.rpm") {
                Text(Formatters.ratePerMile(draft.ratePerMile))
                    .font(.appCaptionMedium)
                    .foregroundStyle(RPMCalculator.band(for: draft.ratePerMile).tint)
            }
        }
    }
}

/// Stop list with add, reorder and delete.
struct StopsSection: View {
    @Binding var stops: [StopDraft]
    let onEdit: (Int) -> Void
    let onAdd: (StopType) -> Void
    let onDelete: (IndexSet) -> Void
    let onMove: (IndexSet, Int) -> Void

    var body: some View {
        Section("load.stops") {
            ForEach(Array(stops.indices), id: \.self) { index in
                Button { onEdit(index) } label: {
                    StopRowView(stop: stops[index])
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: onDelete)
            .onMove(perform: onMove)

            HStack {
                Button { onAdd(.pickup) } label: {
                    Label("stop.addPickup", systemImage: "plus.circle")
                }
                Spacer()
                Button { onAdd(.delivery) } label: {
                    Label("stop.addDelivery", systemImage: "plus.circle")
                }
            }
            .font(.appCaptionMedium)
        }
    }
}

/// Identifies which stop the editor sheet is showing.
struct StopEditTarget: Identifiable, Hashable {
    let index: Int
    var id: Int { index }
}

#Preview {
    PreviewHost {
        AddLoadView()
    }
}
