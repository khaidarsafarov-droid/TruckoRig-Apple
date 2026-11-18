import SwiftUI
import UIKit

/// Settlements received, newest first.
struct PaycheckListView: View {

    @Environment(AppState.self) private var appState

    private var paychecks: [Paycheck] { appState.catalog.paychecks }

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
                Text("\(DateUtils.mediumDate(paycheck.date)) · \(String(localized: "analytics.weekTick \(paycheck.weekNumber)"))")
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
        let repository = appState.financeRepository()
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
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double
    @State private var gross: Double
    @State private var date: Date
    @State private var company: String
    @State private var driverName: String
    @State private var notes: String
    @State private var rawText: String?
    @State private var sourceFileName: String?
    @State private var pendingImage: UIImage?
    @State private var scanMessage: String?
    @State private var isScanning = false
    @State private var errorMessage: String?
    @FocusState private var focus: String?

    private var focusBinding: Binding<String?> {
        Binding(get: { focus }, set: { focus = $0 })
    }

    init(paycheck: Paycheck?) {
        self.paycheck = paycheck
        _amount = State(initialValue: paycheck?.amount ?? 0)
        _gross = State(initialValue: paycheck?.grossAmount ?? 0)
        _date = State(initialValue: paycheck?.date ?? Date())
        _company = State(initialValue: paycheck?.company ?? "")
        _driverName = State(initialValue: paycheck?.driverName ?? "")
        _notes = State(initialValue: paycheck?.notes ?? "")
        _rawText = State(initialValue: paycheck?.rawText)
        _sourceFileName = State(initialValue: paycheck?.sourceFileName)
    }

    var body: some View {
        NavigationStack {
            FocusedForm(focus: $focus) {
                Section("paycheck.file") {
                    Text("paycheck.file.hint")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    Text("paycheck.telegram.hint")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    ReceiptCaptureButtons { image in
                        Task { await recognize(image) }
                    }
                    if isScanning { ProgressView("paycheck.parsing") }
                    if let scanMessage {
                        Text(scanMessage)
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                }
                SoftNumberField(title: "paycheck.amount", value: $amount)
                SoftNumberField(title: "paycheck.gross", value: $gross)
                DatePicker("paycheck.date", selection: $date, displayedComponents: .date)
                SoftTextField(title: "paycheck.driver", text: $driverName, autocapitalization: .words)
                SoftTextField(title: "paycheck.company", text: $company)
                SoftTextField(title: "paycheck.notes", text: $notes)
                    .keyboardFocus(KeyboardField.paycheckNotes, in: focusBinding)
            }
            .navigationTitle(paycheck == nil ? "paycheck.add" : "paycheck.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(PaycheckSalaryFields.validate(netText: String(amount)) != nil)
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
        guard PaycheckSalaryFields.validate(netText: String(amount)) == nil else {
            errorMessage = String(localized: "paycheck.error.net")
            return
        }
        let repository = appState.financeRepository()
        let grossValue = gross > 0 ? gross : nil
        do {
            if let paycheck {
                try repository.update(
                    paycheck,
                    amount: amount,
                    date: date,
                    company: company,
                    notes: notes,
                    grossAmount: grossValue,
                    driverName: driverName,
                    rawText: rawText,
                    sourceFileName: sourceFileName
                )
            } else {
                try repository.addPaycheck(
                    amount: amount,
                    date: date,
                    company: company,
                    notes: notes,
                    grossAmount: grossValue,
                    driverName: driverName,
                    rawText: rawText,
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
            scanMessage = String(localized: "paycheck.file.failed")
            return
        }
        rawText = text
        let name = "paycheck-\(UUID().uuidString.prefix(8)).jpg"
        guard let parsed = PaycheckTextParser.parse(text, fileName: name) else {
            scanMessage = String(localized: "paycheck.file.none")
            return
        }
        amount = parsed.netAmount
        if let grossAmount = parsed.grossAmount { gross = grossAmount }
        if let driver = parsed.driverName { driverName = driver }
        if let iso = parsed.weekEndDate ?? parsed.weekStartDate, let parsedDate = Self.date(fromISO: iso) {
            date = parsedDate
        }
        sourceFileName = name
        if let pendingImage {
            sourceFileName = (try? MediaStore(scope: appState.persistence.scope).saveJPEG(pendingImage)) ?? name
        }
        scanMessage = parsed.confidence == "high"
            ? String(localized: "paycheck.file.parsed")
            : String(localized: "paycheck.file.mismatch")
    }

    private static func date(fromISO iso: String) -> Date? {
        let pieces = iso.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var components = DateComponents()
        components.year = pieces[0]
        components.month = pieces[1]
        components.day = pieces[2]
        return Calendar.current.date(from: components)
    }
}
