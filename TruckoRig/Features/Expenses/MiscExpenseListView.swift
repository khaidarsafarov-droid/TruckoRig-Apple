import SwiftUI
import UIKit

/// Parking, scales, wash and other costs, with an optional receipt photo and a CSV share.
struct MiscExpenseListView: View {

    @Environment(AppState.self) private var appState
    @State private var editing: MiscExpense?
    @State private var isAdding = false
    @State private var pendingDelete: MiscExpense?
    @State private var exportURL: ExportedBackup?
    @State private var statusMessage: String?

    private var expenses: [MiscExpense] { appState.catalog.expenses }
    private var total: Double { expenses.reduce(0) { $0 + $1.amount } }

    var body: some View {
        List {
            Section {
                Text("expense.hint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                Text("expense.total \(Formatters.moneyPrecise(total))")
                    .font(.appHeadline)
            }
            .listRowBackground(Color.clear)

            ForEach(expenses) { expense in
                Button { editing = expense } label: { row(expense) }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.forestCard)
                    .swipeActions {
                        Button(role: .destructive) { pendingDelete = expense } label: {
                            Label("action.delete", systemImage: "trash")
                        }
                    }
            }

            if expenses.isEmpty {
                EmptyStateView(
                    systemImage: "receipt",
                    title: "expense.empty.title",
                    message: "expense.empty.message",
                    actionTitle: "expense.add",
                    action: { isAdding = true }
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle("screen.expenses")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { share() } label: {
                    Label("expense.send", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("expense.send")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: {
                    Label("expense.add", systemImage: "plus")
                }
                .accessibilityLabel("expense.add")
            }
        }
        .sheet(isPresented: $isAdding) { MiscExpenseEditor(expense: nil) }
        .sheet(item: $editing) { expense in MiscExpenseEditor(expense: expense) }
        .sheet(item: $exportURL) { export in ShareSheet(items: [export.url]) }
        .confirmationDialog("expense.delete.title", isPresented: .isPresented($pendingDelete), titleVisibility: .visible) {
            Button("action.delete", role: .destructive) { deletePending() }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("expense.delete.message")
        }
        .alert(
            "error.title",
            isPresented: .isPresented($statusMessage),
            actions: { Button("action.ok") {} },
            message: { Text(statusMessage ?? "") }
        )
    }

    private func row(_ expense: MiscExpense) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.expenseDescription)
                    .font(.appBodyMedium)
                    .foregroundStyle(Color.forestText)
                Text(DateUtils.mediumDate(expense.date))
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                if expense.receiptFileName != nil {
                    Label("expense.receipt.attached", systemImage: "paperclip")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
            }
            Spacer()
            Text(Formatters.moneyPrecise(expense.amount))
                .font(.appNumber)
                .foregroundStyle(Color.forestPrimary)
        }
    }

    private func share() {
        guard !expenses.isEmpty else {
            statusMessage = String(localized: "expense.send.empty")
            return
        }
        let rows = expenses.map { expense in
            (
                date: iso(expense.date),
                description: expense.expenseDescription,
                amount: expense.amount,
                receipt: expense.receiptFileName == nil ? "" : "yes"
            )
        }
        let csv = MiscExpenseFields.csv(rows: rows)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("truckorig-expenses.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportURL = ExportedBackup(url: url)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func deletePending() {
        guard let expense = pendingDelete else { return }
        pendingDelete = nil
        do { try appState.financeRepository().delete(expense) } catch { statusMessage = error.localizedDescription }
    }

    private func iso(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

struct MiscExpenseEditor: View {
    let expense: MiscExpense?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double
    @State private var descriptionText: String
    @State private var date: Date
    @State private var receiptFileName: String?
    @State private var pendingImage: UIImage?
    @State private var errorMessage: String?

    init(expense: MiscExpense?) {
        self.expense = expense
        _amount = State(initialValue: expense?.amount ?? 0)
        _descriptionText = State(initialValue: expense?.expenseDescription ?? "")
        _date = State(initialValue: expense?.date ?? Date())
        _receiptFileName = State(initialValue: expense?.receiptFileName)
    }

    var body: some View {
        NavigationStack {
            Form {
                SoftNumberField(title: "expense.amount", value: $amount)
                SoftTextField(title: "expense.description", text: $descriptionText, placeholder: "expense.description.hint")
                DatePicker("expense.date", selection: $date, displayedComponents: .date)
                Section("expense.receipt") {
                    Text("expense.receipt.hint")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    ReceiptCaptureButtons { image in
                        pendingImage = image
                        receiptFileName = receiptFileName ?? "pending"
                    }
                    if pendingImage != nil || receiptFileName != nil {
                        Label("expense.receipt.attached", systemImage: "checkmark.circle")
                        Button("expense.receipt.remove", role: .destructive) {
                            pendingImage = nil
                            receiptFileName = nil
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.appCaption).foregroundStyle(Color.forestError)
                }
            }
            .navigationTitle(expense == nil ? "expense.add" : "expense.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let iso = {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }()
        if let failure = MiscExpenseFields.validate(
            amountText: String(amount),
            description: descriptionText,
            dateISO: iso
        ) {
            switch failure {
            case .amount: errorMessage = String(localized: "expense.error.amount")
            case .description: errorMessage = String(localized: "expense.error.description")
            case .date: errorMessage = String(localized: "expense.error.date")
            }
            return
        }
        let fileName = storedReceiptName()
        do {
            let repository = appState.financeRepository()
            if let expense {
                try repository.update(expense, amount: amount, description: descriptionText, date: date, receiptFileName: fileName)
            } else {
                try repository.addExpense(amount: amount, description: descriptionText, date: date, receiptFileName: fileName)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func storedReceiptName() -> String? {
        if let pendingImage {
            let store = MediaStore(scope: appState.persistence.scope)
            return try? store.saveJPEG(pendingImage)
        }
        return receiptFileName == "pending" ? nil : receiptFileName
    }
}
