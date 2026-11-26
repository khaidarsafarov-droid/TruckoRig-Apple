import SwiftUI

/// "Load cancelled" form: the driver enters the TONU pay the broker agreed to.
///
/// $175 (Amazon Relay) and $225 (typical broker) are quick picks only. Any amount can be typed,
/// and "No pay" records a cancellation without TONU. A new cancellation asks once more before
/// it changes the load; editing the TONU of an already cancelled load saves directly.
struct LoadCancelSheet: View {
    let load: Load
    let onConfirm: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double
    @State private var noPay: Bool
    @State private var isConfirming = false
    private let inWindow: Bool

    init(load: Load, now: Date = Date(), onConfirm: @escaping (Double) -> Void) {
        self.load = load
        self.onConfirm = onConfirm
        let pickup = load.scheduledPickupAt
        let suggested = LoadCancellation.suggestedAmount(for: load.cancellationState, pickup: pickup, now: now)
        _amount = State(initialValue: suggested ?? 0)
        _noPay = State(initialValue: suggested == 0)
        inWindow = !load.isCancelled && LoadCancellation.isWithinTonuWindow(pickup: pickup, now: now)
    }

    private var titleKey: LocalizedStringKey {
        load.isCancelled ? "load.cancel.edit.title" : "load.cancel.title"
    }

    private var introKey: LocalizedStringKey {
        load.isCancelled ? "load.cancel.edit.body" : "load.cancel.body"
    }

    private var confirmKey: LocalizedStringKey {
        load.isCancelled ? "load.cancel.save" : "load.cancel.confirm"
    }

    private var isValid: Bool {
        (amount > 0 || noPay) && LoadCancellation.isValidTonu(amount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    Text(introKey)
                        .font(.appBody)
                        .foregroundStyle(Color.forestTextSecondary)
                    if inWindow {
                        Label("load.cancel.window", systemImage: "clock.badge.exclamationmark")
                            .font(.appCaptionMedium)
                            .foregroundStyle(Color.forestWarning)
                            .padding(10)
                            .background(Color.warningContainer, in: RoundedRectangle(cornerRadius: 12))
                    }
                    quickPicks
                    SoftNumberField(title: "load.cancel.tonu", value: $amount, money: true)
                        .onChange(of: amount) { _, newValue in
                            if newValue > 0 { noPay = false }
                        }
                    Text("load.cancel.hint")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    SoftButton(
                        title: confirmKey,
                        systemImage: "xmark.circle",
                        role: load.isCancelled ? .primary : .destructive
                    ) {
                        submit()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("uitest.cancelLoad.confirm")
                }
                .padding(Spacing.standard)
            }
            .forestBackground()
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.back") { dismiss() }
                }
            }
            .alert("load.cancel.confirm.title", isPresented: $isConfirming) {
                Button("load.cancel.confirm", role: .destructive) { apply() }
                Button("action.back", role: .cancel) {}
            } message: {
                Text("load.cancel.confirm.body \(Formatters.moneyPrecise(amount))")
            }
        }
        .presentationDetents([.large])
    }

    private var quickPicks: some View {
        HStack(spacing: 8) {
            ForEach(LoadCancellation.suggestedTonu, id: \.self) { value in
                pick(
                    value == LoadCancellation.suggestedTonu.first
                        ? String(localized: "load.cancel.tonu.amazon \(Formatters.money(value))")
                        : String(localized: "load.cancel.tonu.broker \(Formatters.money(value))"),
                    selected: !noPay && abs(amount - value) < 0.005
                ) {
                    noPay = false
                    amount = value
                }
            }
            pick(String(localized: "load.cancel.noPay"), selected: noPay) {
                noPay = true
                amount = 0
            }
        }
    }

    private func pick(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appCaptionMedium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? Color.forestOnPrimary : Color.forestPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(selected ? Color.forestPrimary : Color.forestPrimary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func submit() {
        guard isValid else { return }
        if load.isCancelled {
            apply()
        } else {
            isConfirming = true
        }
    }

    private func apply() {
        onConfirm(noPay ? 0 : amount)
        dismiss()
    }
}

/// Shown on the load detail instead of the active-load chips once a load is cancelled.
struct LoadCancelledCard: View {
    let load: Load
    var onEdit: () -> Void
    var onRestore: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        SoftCard {
            HStack {
                LoadCancelledBadge(tonu: load.totalRate)
                Spacer()
                if let cancelledAt = load.cancelledAt {
                    Text(DateUtils.dateTime(cancelledAt))
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
            }
            if let original = originalLine {
                Text(original)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            HStack(spacing: Spacing.tight) {
                SoftButton(title: "load.cancel.editTonu", systemImage: "pencil", role: .secondary, action: onEdit)
                    .accessibilityIdentifier("uitest.cancelLoad.edit")
                SoftButton(
                    title: "load.cancel.undo",
                    systemImage: "arrow.uturn.backward",
                    role: .secondary,
                    action: onRestore
                )
                .accessibilityIdentifier("uitest.cancelLoad.restore")
            }
        }
    }

    private var originalLine: String? {
        guard let rate = load.originalRate else { return nil }
        let miles = Formatters.miles(load.originalMiles ?? 0, system: appState.settings.measurementSystem)
        return String(localized: "load.cancel.original \(Formatters.moneyPrecise(rate)) \(miles)")
    }
}

/// "Cancelled · TONU $175" capsule for the detail card and journal rows.
struct LoadCancelledBadge: View {
    let tonu: Double

    var body: some View {
        Text(title)
            .font(.appCaptionMedium)
            .foregroundStyle(Color.forestWarning)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.warningContainer, in: Capsule())
            .accessibilityIdentifier("uitest.load.cancelledBadge")
    }

    private var title: String {
        guard tonu > 0 else { return String(localized: "load.cancel.badge") }
        return String(localized: "load.cancel.badge.tonu \(Formatters.moneyPrecise(tonu))")
    }
}
