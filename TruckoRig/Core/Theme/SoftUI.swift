import SwiftUI

/// Shared spacing and radii for the soft UI. Screens reference these instead of literals so the
/// rhythm stays consistent when a screen is added later.
/// Radii from Android `OneUiTokens`: chip 8, card 12, card-large and button 16.
enum Spacing {
    static let tight: CGFloat = 8
    static let standard: CGFloat = 16
    static let section: CGFloat = 20
    static let chipRadius: CGFloat = 8
    static let cardRadius: CGFloat = 12
    static let cardLargeRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 16
    /// Fields and compact controls use the card radius.
    static let controlRadius: CGFloat = 12
}

private struct SoftCardModifier: ViewModifier {
    var padding: CGFloat
    var background: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
            .softShadow()
    }
}

private struct SoftShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // A light drop shadow disappears on a dark background; a hairline border reads instead.
        content
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 8, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous)
                    .strokeBorder(Color.forestSeparator.opacity(colorScheme == .dark ? 1 : 0), lineWidth: 1)
            )
    }
}

extension View {
    func softCard(padding: CGFloat = Spacing.standard, background: Color = .forestCard) -> some View {
        modifier(SoftCardModifier(padding: padding, background: background))
    }

    func softShadow() -> some View {
        modifier(SoftShadowModifier())
    }

    /// Standard screen chrome: forest background edge to edge.
    func forestBackground() -> some View {
        background(Color.forestBackground.ignoresSafeArea())
    }
}

/// Applies the saved theme to a screen tree. OLED black is on only when the cabin is dark.
struct AppCabinTheme: ViewModifier {
    @Environment(\.colorScheme) private var systemScheme
    var mode: AppThemeMode
    var oledDark: Bool

    private var oledActive: Bool {
        ThemePalette.oledApplies(mode: mode, oledDark: oledDark, systemIsDark: systemScheme == .dark)
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(mode.preferredColorScheme)
            .environment(\.oledDarkActive, oledActive)
            .background {
                OLEDTraitInstaller(active: oledActive)
            }
            .modifier(OLEDBarChrome(active: oledActive))
    }
}

/// True-black navigation and tab bars. Left off unless OLED is on, so the system bars stay as they are.
private struct OLEDBarChrome: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .toolbarBackground(Color.forestBackground, for: .navigationBar)
                .toolbarBackground(Color.forestBackground, for: .tabBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.visible, for: .tabBar)
        } else {
            content
        }
    }
}

struct SoftPrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appBodyMedium)
            .foregroundStyle(Color.forestOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                (isDestructive ? Color.forestError : Color.forestPrimary)
                    .opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: Spacing.buttonRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Champagne gold primary action. Espresso label so the text stays readable on the gold.
struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appBodyMedium)
            .foregroundStyle(Color.goldOnGold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [Color.goldStart, Color.goldEnd], startPoint: .leading, endPoint: .trailing)
                    .opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: Spacing.buttonRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SoftSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appBodyMedium)
            .foregroundStyle(Color.forestPrimary.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Color.forestSurfaceMuted,
                in: RoundedRectangle(cornerRadius: Spacing.buttonRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SoftPrimaryButtonStyle {
    static var softPrimary: SoftPrimaryButtonStyle { SoftPrimaryButtonStyle() }
    static var softDestructive: SoftPrimaryButtonStyle { SoftPrimaryButtonStyle(isDestructive: true) }
}

extension ButtonStyle where Self == SoftSecondaryButtonStyle {
    static var softSecondary: SoftSecondaryButtonStyle { SoftSecondaryButtonStyle() }
}
