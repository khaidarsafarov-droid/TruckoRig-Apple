import SwiftData
import SwiftUI

/// Settlements received, newest first.
struct PaycheckListView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Paycheck.date, order: .reverse) private var paychecks: [Paycheck]

    @State private var editing: Paycheck?
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var total: Double { paychecks.reduce(0) { $0 + $1.amount } }

    var body: some View {
        List {
            if !paychecks.isEmpty {
                Section {
                    HStack {
                        StatTile(title: "paycheck.total", value: Formatters.money(total))
                        StatTile(title: "paycheck.count", value: "\(paychecks.count)")
                    }
                }
                .listRowBackground(Color.forestCard)
            }

            ForEach(paychecks) { paycheck in
                Button { editing = paycheck } label: {
                    row(paycheck)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.forestCard)
                .swipeActions {
                    Button(role: .destructive) { delete(paycheck) } label: {
                        Label("action.delete", systemImage: "trash")
                    }
                }
            }

            if paychecks.isEmpty {
                EmptyStateView(
                    systemImage: "dollarsign.circle",
                    title: "paycheck.empty.title",
                    message: "paycheck.empty.message",
                    actionTitle: "paycheck.add",
                    action: { isAdding = true }
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle("screen.paycheck")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: {
                    Label("paycheck.add", systemImage: "plus")
                }
                .accessibilityLabel("paycheck.add")
            }
        }
        .sheet(isPresented: $isAdding) {
            PaycheckEditorView(paycheck: nil)
        }
        .sheet(item: $editing) { paycheck in
            PaycheckEditorView(paycheck: paycheck)
        }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private func row(_ paycheck: Paycheck) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(paycheck.company ?? String(localized: "paycheck.untitled"))
                    .font(.appBodyMedium)
                    .foregroundStyle(Color.forestText)
                Text("\(DateUtils.mediumDate(paycheck.date)) · W\(paycheck.weekNumber)" as String)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            Spacer()
            Text(Formatters.moneyPrecise(paycheck.amount))
                .font(.appNumber)
                .foregroundStyle(Color.forestPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func delete(_ paycheck: Paycheck) {
        let repository = appState.financeRepository(in: modelContext)
        do {
            try repository.delete(paycheck)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Add or edit one settlement.
struct PaycheckEditorView: View {

    let paycheck: Paycheck?

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double
    @State private var date: Date
    @State private var company: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(paycheck: Paycheck?) {
        self.paycheck = paycheck
        _amount = State(initialValue: paycheck?.amount ?? 0)
        _date = State(initialValue: paycheck?.date ?? Date())
        _company = State(initialValue: paycheck?.company ?? "")
        _notes = State(initialValue: paycheck?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                SoftNumberField(title: "paycheck.amount", value: $amount)
                DatePicker("paycheck.date", selection: $date, displayedComponents: .date)
                SoftTextField(title: "paycheck.company", text: $company)
                SoftTextField(title: "paycheck.notes", text: $notes)
            }
            .navigationTitle(paycheck == nil ? "paycheck.add" : "paycheck.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(amount <= 0)
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
        do {
            if let paycheck {
                try repository.update(paycheck, amount: amount, date: date, company: company, notes: notes)
            } else {
                try repository.addPaycheck(amount: amount, date: date, company: company, notes: notes)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
