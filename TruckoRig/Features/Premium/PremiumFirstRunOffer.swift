import SwiftUI

/// Once, after the journal is on screen. The free month starts only if the driver subscribes.
struct PremiumFirstRunOffer: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let premium = appState.premium
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("premium.offer.title")
                    .font(.appLargeTitle)
                    .foregroundStyle(Color.brandGold)
                    .fixedSize(horizontal: false, vertical: true)
                Text("premium.offer.price \(premium.displayPrice)")
                    .font(.appHeadline)
                    .foregroundStyle(Color.forestText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("premium.offer.body")
                    .font(.appBody)
                    .foregroundStyle(Color.forestTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                feature("premium.offer.feature.telegram")
                feature("premium.offer.feature.insights")
                feature("premium.offer.feature.tools")
                Text("premium.terms")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await premium.purchase() }
                } label: {
                    Text("premium.subscribe")
                }
                .buttonStyle(GoldButtonStyle())
                .accessibilityIdentifier("truckorig.firstRun.subscribe")
                Button {
                    premium.declineFirstRun()
                } label: {
                    Text("premium.offer.continue")
                        .font(.appBodyMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .foregroundStyle(Color.forestTextSecondary)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .forestBackground()
        .alert(
            "error.title",
            isPresented: Binding(
                get: { premium.purchaseError != nil },
                set: { if !$0 { premium.clearPurchaseError() } }
            ),
            actions: { Button("action.ok") { premium.clearPurchaseError() } },
            message: { Text(premium.purchaseError ?? "") }
        )
        .onChange(of: premium.isActive) { _, active in
            if active { premium.declineFirstRun() }
        }
    }

    private func feature(_ key: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.appBodyMedium)
                .foregroundStyle(Color.brandGold)
            Text(key)
                .font(.appBody)
                .foregroundStyle(Color.forestText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
