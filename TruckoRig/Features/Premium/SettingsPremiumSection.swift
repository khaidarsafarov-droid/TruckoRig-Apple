import SwiftUI

/// Dismissable note on the settings Premium block, three days before the free month ends.
struct TrialEndReminderBanner: View {
    var text: String
    var onDismiss: () -> Void
    var onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                Text(text)
                    .font(.appBody)
                    .foregroundStyle(Color.heroText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.appBodyMedium)
                        .foregroundStyle(Color.heroText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(Text("premium.close"))
            }
            Button(action: onManage) {
                Text("settings.premium.manage")
            }
            .buttonStyle(GoldButtonStyle())
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Spacing.cardLargeRadius, style: .continuous))
    }
}

/// Premium block on Settings: status, the trial banner, and subscription management.
struct SettingsPremiumSection: View {
    @Environment(AppState.self) private var appState
    @State private var showPaywall = false

    var body: some View {
        let premium = appState.premium
        VStack(alignment: .leading, spacing: 12) {
            Text("premium.title")
                .font(.appHeadline)
                .foregroundStyle(Color.heroText)
            if premium.isActive {
                Text("premium.active")
                    .font(.appBody)
                    .foregroundStyle(Color.heroText)
                Text("settings.premium.renews")
                    .font(.appCaption)
                    .foregroundStyle(Color.heroTextMuted)
                if premium.shouldShowBanner {
                    TrialEndReminderBanner(
                        text: premium.reminderText,
                        onDismiss: { premium.dismissBanner() },
                        onManage: { Task { await premium.manage() } }
                    )
                }
                Button {
                    Task { await premium.manage() }
                } label: {
                    Text("settings.premium.manage")
                }
                .buttonStyle(GoldButtonStyle())
            } else {
                Text("premium.free")
                    .font(.appBody)
                    .foregroundStyle(Color.heroText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("premium.terms")
                    .font(.appCaption)
                    .foregroundStyle(Color.heroTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showPaywall = true
                } label: {
                    Text("premium.subscribe")
                }
                .buttonStyle(GoldButtonStyle())
                Button {
                    Task { await premium.restore() }
                } label: {
                    Text("premium.restore")
                        .font(.appBodyMedium)
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(Color.heroText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            HeroGradient()
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cardLargeRadius, style: .continuous))
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallSheet(onClose: { showPaywall = false })
                .environment(appState)
        }
    }
}

struct PremiumPaywallSheet: View {
    @Environment(AppState.self) private var appState
    var onClose: () -> Void

    var body: some View {
        PaywallView(
            priceText: appState.premium.displayPrice,
            includesFreeMonth: appState.premium.includesFreeMonth,
            isLoading: !appState.premium.didRefresh,
            onSubscribe: { Task { await appState.premium.purchase() } },
            onRestore: { Task { await appState.premium.restore() } },
            onClose: onClose
        )
        .alert(
            "error.title",
            isPresented: Binding(
                get: { appState.premium.purchaseError != nil },
                set: { if !$0 { appState.premium.clearPurchaseError() } }
            ),
            actions: { Button("action.ok") { appState.premium.clearPurchaseError() } },
            message: { Text(appState.premium.purchaseError ?? "") }
        )
    }
}
