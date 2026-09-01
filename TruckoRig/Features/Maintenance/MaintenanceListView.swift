import SwiftData
import SwiftUI

/// Service items: due, done and archived.
struct MaintenanceListView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MaintenanceTask.dueDate) private var tasks: [MaintenanceTask]

    @State private var editing: MaintenanceTask?
    @State private var isAdding = false
    @State private var showsArchived = false
    @State private var errorMessage: String?

    private var visible: [MaintenanceTask] {
        tasks.filter { $0.isArchived == showsArchived }
    }

    private var open: [MaintenanceTask] { visible.filter { !$0.isCompleted } }
    private var done: [MaintenanceTask] { visible.filter(\.isCompleted) }

    var body: some View {
        List {
            if !open.isEmpty {
                Section("maintenance.open") {
                    ForEach(open) { task in
                        taskRow(task)
                    }
                }
            }
            if !done.isEmpty {
                Section("maintenance.done") {
                    ForEach(done) { task in
                        taskRow(task)
                    }
                }
            }
            if visible.isEmpty {
                emptyState
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle("screen.maintenance")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showsArchived.toggle()
                } label: {
                    Label("maintenance.archive", systemImage: showsArchived ? "archivebox.fill" : "archivebox")
                }
                .accessibilityLabel("maintenance.archive")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: {
                    Label("maintenance.add", systemImage: "plus")
                }
                .accessibilityLabel("maintenance.add")
            }
        }
        .sheet(isPresented: $isAdding) { MaintenanceEditorView(task: nil) }
        .sheet(item: $editing) { task in MaintenanceEditorView(task: task) }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    /// The archive has nothing to add, so it shows the same placeholder without an action.
    private var emptyState: some View {
        let addAction: (() -> Void)? = showsArchived ? nil : { isAdding = true }
        let actionTitle: LocalizedStringKey? = showsArchived ? nil : "maintenance.add"

        return EmptyStateView(
            systemImage: "wrench.and.screwdriver",
            title: showsArchived ? "maintenance.archive.empty.title" : "maintenance.empty.title",
            message: showsArchived ? "maintenance.archive.empty.message" : "maintenance.empty.message",
            actionTitle: actionTitle,
            action: addAction
        )
        .listRowBackground(Color.clear)
    }

    private func taskRow(_ task: MaintenanceTask) -> some View {
        HStack {
            Button {
                setCompleted(task, completed: !task.isCompleted)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.forestSuccess : Color.forestTextSecondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.isCompleted ? "maintenance.markOpen" : "maintenance.markDone")

            Button { editing = task } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.appBodyMedium)
                            .foregroundStyle(Color.forestText)
                            .strikethrough(task.isCompleted)
                        Text(subtitle(task))
                            .font(.appCaption)
                            .foregroundStyle(task.isOverdue() ? Color.forestError : Color.forestTextSecondary)
                    }
                    Spacer()
                    if let cost = task.cost {
                        Text(Formatters.moneyPrecise(cost))
                            .font(.appCaptionMedium)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.forestCard)
        .swipeActions {
            Button(role: .destructive) { delete(task) } label: {
                Label("action.delete", systemImage: "trash")
            }
            Button { setArchived(task, archived: !task.isArchived) } label: {
                Label("maintenance.archive", systemImage: "archivebox")
            }
            .tint(Color.forestSecondary)
        }
    }

    private func subtitle(_ task: MaintenanceTask) -> String {
        var parts: [String] = []
        if let dueDate = task.dueDate { parts.append(DateUtils.mediumDate(dueDate)) }
        if let odometer = task.dueOdometer { parts.append("\(odometer.formatted()) mi") }
        if let completed = task.completedDate {
            parts.append(String(localized: "maintenance.completedOn \(DateUtils.mediumDate(completed))"))
        }
        return parts.joined(separator: " · ")
    }

    private var repository: FinanceRepository {
        FinanceRepository(context: modelContext, sync: appState.sync, week: appState.settings.truckingWeek)
    }

    private func setCompleted(_ task: MaintenanceTask, completed: Bool) {
        do { try repository.setCompleted(task, completed: completed) } catch { errorMessage = error.localizedDescription }
    }

    private func setArchived(_ task: MaintenanceTask, archived: Bool) {
        do { try repository.setArchived(task, archived: archived) } catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ task: MaintenanceTask) {
        do { try repository.delete(task) } catch { errorMessage = error.localizedDescription }
    }
}

/// Add or edit a service item.
struct MaintenanceEditorView: View {

    let task: MaintenanceTask?

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var odometerText: String
    @State private var cost: Double
    @State private var notes: String
    @State private var errorMessage: String?

    init(task: MaintenanceTask?) {
        self.task = task
        _title = State(initialValue: task?.title ?? "")
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? Date())
        _odometerText = State(initialValue: task?.dueOdometer.map(String.init) ?? "")
        _cost = State(initialValue: task?.cost ?? 0)
        _notes = State(initialValue: task?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                SoftTextField(title: "maintenance.title", text: $title)
                Toggle("maintenance.hasDueDate", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("maintenance.dueDate", selection: $dueDate, displayedComponents: .date)
                }
                SoftTextField(title: "maintenance.dueOdometer", text: $odometerText, keyboard: .numberPad)
                SoftNumberField(title: "maintenance.cost", value: $cost)
                SoftTextField(title: "maintenance.notes", text: $notes)
            }
            .navigationTitle(task == nil ? "maintenance.add" : "maintenance.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(title.trimmed.isEmpty)
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
        let repository = FinanceRepository(
            context: modelContext,
            sync: appState.sync,
            week: appState.settings.truckingWeek
        )
        let odometer = Int(odometerText.filter(\.isNumber))
        do {
            if let task {
                try repository.update(
                    task,
                    title: title.trimmed,
                    dueDate: hasDueDate ? dueDate : nil,
                    dueOdometer: odometer,
                    cost: cost > 0 ? cost : nil,
                    notes: notes
                )
            } else {
                try repository.addTask(
                    title: title.trimmed,
                    dueDate: hasDueDate ? dueDate : nil,
                    dueOdometer: odometer,
                    cost: cost > 0 ? cost : nil,
                    notes: notes
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
