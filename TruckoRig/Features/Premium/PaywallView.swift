import SwiftUI
import UIKit

/// Bottom obstruction for the paywall. The larger of the safe area and the keyboard, never the sum.
enum PaywallInsets {
    static func bottom(safeArea: CGFloat, keyboard: CGFloat) -> CGFloat {
        max(safeArea, keyboard)
    }
}

struct PaywallButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.height > 0 { value = next }
    }
}

struct PaywallContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Records where the subscribe button landed so the layout test can measure it.
final class PaywallLayoutProbe {
    var subscribeFrame: CGRect = .zero
    var contentHeight: CGFloat = 0
}

/// Paywall. The content scrolls, and the subscribe button stays above the taller bottom obstruction.
struct PaywallView: View {
    var priceText: String
    var includesFreeMonth: Bool
    var isLoading: Bool
    /// Home-indicator (or test) inset. `nil` reads the safe area.
    var safeAreaBottom: CGFloat?
    var keyboardHeight: CGFloat = 0
    var layoutProbe: PaywallLayoutProbe?
    var onSubscribe: () -> Void
    var onRestore: () -> Void
    var onClose: () -> Void

    @State private var observedKeyboard: CGFloat = 0

    private var keyboard: CGFloat {
        keyboardHeight > 0 ? keyboardHeight : observedKeyboard
    }

    var body: some View {
        GeometryReader { proxy in
            let safe = safeAreaBottom ?? proxy.safeAreaInsets.bottom
            let inset = PaywallInsets.bottom(safeArea: safe, keyboard: keyboard)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("premium.title")
                            .font(.appTitle)
                            .foregroundStyle(Color.heroText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background {
                                HeroGradient()
                                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cardLargeRadius, style: .continuous))
                            }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("premium.body")
                                .font(.appBody)
                                .foregroundStyle(Color.forestText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("paywall.body")
                            PaywallIncludedSection()
                            Text("premium.terms")
                                .font(.appCaption)
                                .foregroundStyle(Color.forestTextSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(action: onSubscribe) {
                                Text(subscribeLabel)
                            }
                            .buttonStyle(GoldButtonStyle())
                            .accessibilityIdentifier("paywall.subscribe")
                            .id(Self.subscribeID)
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: PaywallButtonFrameKey.self,
                                        value: geo.frame(in: .global)
                                    )
                                }
                            }
                            Button(action: onRestore) {
                                Text("premium.restore")
                                    .font(.appBodyMedium)
                                    .frame(maxWidth: .infinity)
                            }
                            Button(action: onClose) {
                                Text("premium.back")
                                    .font(.appBody)
                                    .frame(maxWidth: .infinity)
                            }
                            .foregroundStyle(Color.forestTextSecondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.forestCard, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
                    }
                    .padding(16)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: PaywallContentHeightKey.self, value: geo.size.height)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: inset)
                }
                .onAppear {
                    guard layoutProbe != nil else { return }
                    DispatchQueue.main.async {
                        scroll.scrollTo(Self.subscribeID, anchor: .bottom)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(Color.forestBackground.ignoresSafeArea())
        .onPreferenceChange(PaywallButtonFrameKey.self) { frame in
            layoutProbe?.subscribeFrame = frame
        }
        .onPreferenceChange(PaywallContentHeightKey.self) { height in
            layoutProbe?.contentHeight = height
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenMaxY = UIScreen.main.bounds.maxY
            observedKeyboard = max(0, screenMaxY - frame.minY)
        }
    }

    private var subscribeLabel: LocalizedStringKey {
        if isLoading { return "premium.price.loading" }
        if includesFreeMonth { return "premium.subscribe.price \(priceText)" }
        return "premium.subscribe.paid \(priceText)"
    }

    static let subscribeID = "paywall.subscribe"
}
