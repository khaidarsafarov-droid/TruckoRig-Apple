import SwiftUI

/// Hides a paid screen until StoreKit says the subscription is active.
///
/// Android wraps the same screens in `PremiumGate`. The journal itself stays free.
struct PremiumGateModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    let message: LocalizedStringKey

    func body(content: Content) -> some View {
        if !appState.premium.didRefresh {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .forestBackground()
        } else if appState.premium.isActive {
            content
        } else {
            PremiumLockedPane(message: message)
        }
    }
}

struct PremiumLockedPane: View {
    @Environment(AppState.self) private var appState
    let message: LocalizedStringKey
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            Text(message)
                .font(.appBody)
                .foregroundStyle(Color.forestText)
            Button("premium.subscribe") { showPaywall = true }
                .buttonStyle(.softPrimary)
        }
        .padding(Spacing.standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .forestBackground()
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallSheet(onClose: { showPaywall = false })
                .environment(appState)
        }
    }
}

extension View {
    func premiumGated(_ message: LocalizedStringKey) -> some View {
        modifier(PremiumGateModifier(message: message))
    }
}
