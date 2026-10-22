import SwiftUI
import UIKit

extension Color {
    /// `#RRGGBB` or `#RRGGBBAA`. Falls back to clear rather than trapping on a bad literal.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        guard let value = UInt64(cleaned, radix: 16), cleaned.count == 6 || cleaned.count == 8 else {
            self = .clear
            return
        }
        let hasAlpha = cleaned.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Builds a colour that follows the interface style.
    ///
    /// Dark mode is a separate cabin palette, not a tint of the light one, so each token names
    /// both variants. Values come from Android `SoftUiColors`, `BrandPalettes` and `SemanticColors`.
    static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: CabinUIColors.adaptive(light: light, dark: dark, oled: nil))
    }

    /// Same as `adaptive`, with Android's true-black OLED override when the dark cabin is active.
    static func adaptiveSurface(light: String, dark: String, oled: String) -> Color {
        Color(uiColor: CabinUIColors.adaptive(light: light, dark: dark, oled: oled))
    }
}

/// True-black OLED flag bridged into `UITraitCollection` so every `Color.forest*` surface updates.
struct OLEDDarkTrait: UITraitDefinition {
    static let defaultValue = false
    static let affectsColorAppearance = true
    static let name = "com.truckorig.oledDark"
}

private struct OLEDDarkActiveKey: UITraitBridgedEnvironmentKey {
    static let defaultValue = false

    static func read(from traitCollection: UITraitCollection) -> Bool {
        traitCollection[OLEDDarkTrait.self]
    }

    static func write(to mutableTraits: inout UIMutableTraits, value: Bool) {
        mutableTraits[OLEDDarkTrait.self] = value
    }
}

extension EnvironmentValues {
    /// Resolved OLED black. True only when the driver asked for it and the cabin is actually dark.
    var oledDarkActive: Bool {
        get { self[OLEDDarkActiveKey.self] }
        set { self[OLEDDarkActiveKey.self] = newValue }
    }
}

enum CabinUIColors {
    static let background = adaptive(
        light: ThemePalette.backgroundLight,
        dark: ThemePalette.backgroundDark,
        oled: ThemePalette.backgroundOled
    )
    static let card = adaptive(
        light: ThemePalette.surfaceLight,
        dark: ThemePalette.surfaceDark,
        oled: ThemePalette.surfaceOled
    )
    static let muted = adaptive(
        light: ThemePalette.surfaceMutedLight,
        dark: ThemePalette.surfaceMutedDark,
        oled: ThemePalette.surfaceMutedOled
    )

    static func adaptive(light: String, dark: String, oled: String?) -> UIColor {
        UIColor { traits in
            let darkMode = traits.userInterfaceStyle == .dark
            let hex: String
            if darkMode, let oled, traits[OLEDDarkTrait.self] {
                hex = oled
            } else {
                hex = darkMode ? dark : light
            }
            return UIColor(Color(hex: hex))
        }
    }
}

/// Pushes the OLED trait onto the window so UIKit bars resolve the same surfaces as SwiftUI.
struct OLEDTraitInstaller: UIViewControllerRepresentable {
    var active: Bool

    func makeUIViewController(context: Context) -> OLEDTraitController {
        let controller = OLEDTraitController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: OLEDTraitController, context: Context) {
        controller.active = active
    }
}

final class OLEDTraitController: UIViewController {
    var active = false {
        didSet { apply() }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        apply()
    }

    private func apply() {
        guard let window = view.window else { return }
        guard window.traitOverrides[OLEDDarkTrait.self] != active else { return }
        window.traitOverrides[OLEDDarkTrait.self] = active
        window.backgroundColor = CabinUIColors.background
    }
}

/// Midnight & Gold.
///
/// Token names that start with `forest` are the Android names (`ForestPrimary` and friends).
/// The greens are gone; the values are the indigo / gold cabin palette.
extension Color {
    /// Light `#3F3D9E`. Dark primary buttons are champagne gold `#D6BC85`, not inverted indigo.
    static let forestPrimary = Color.adaptive(light: "3F3D9E", dark: "D6BC85")
    /// `OnContainer` — secondary indigo ink on the light canvas, lifted lilac in the dark cabin.
    static let forestSecondary = Color.adaptive(light: "25265E", dark: "E2DFF5")
    /// Same fill as `forestPrimary` (Android `ForestAccent` / `ForestAccentDark`).
    static let forestAccent = Color.forestPrimary

    /// Page canvas. Light `#F5F4F1`, dark `#0D0F1E`, OLED `#000000`.
    static let forestBackground = Color.adaptiveSurface(
        light: ThemePalette.backgroundLight,
        dark: ThemePalette.backgroundDark,
        oled: ThemePalette.backgroundOled
    )
    /// Card surface. Light `#FDFCFA`, dark `#161929`, OLED `#121212`.
    static let forestCard = Color.adaptiveSurface(
        light: ThemePalette.surfaceLight,
        dark: ThemePalette.surfaceDark,
        oled: ThemePalette.surfaceOled
    )
    /// Input and chip wash. Light sage `#EAE9F4`, dark `#262A4F`, OLED `#1C1C1C`.
    static let forestSurfaceMuted = Color.adaptiveSurface(
        light: ThemePalette.surfaceMutedLight,
        dark: ThemePalette.surfaceMutedDark,
        oled: ThemePalette.surfaceMutedOled
    )

    static let forestText = Color.adaptive(light: "16182B", dark: "EEEBE3")
    static let forestTextSecondary = Color.adaptive(light: "585A6E", dark: "A7A6B4")
    static let forestSeparator = Color.adaptive(light: "E6E2D8", dark: "262A3E")

    static let forestSuccess = Color.adaptive(light: "3D6A55", dark: "8FBFA6")
    static let forestWarning = Color.adaptive(light: "86542A", dark: "DDAE84")
    static let forestError = Color.adaptive(light: "953C46", dark: "E39AA2")

    /// White on indigo. Espresso `#1D1708` on the dark-mode gold button so it clears AA.
    static let forestOnPrimary = Color.adaptive(light: "FFFFFF", dark: "1D1708")

    // MARK: Hero

    /// Horizontal hero wash. Light `#1E2150` → `#0F1230`.
    static let heroStart = Color.adaptive(light: "1E2150", dark: "1E2250")
    static let heroEnd = Color.adaptive(light: "0F1230", dark: "111430")
    static let heroText = Color.adaptive(light: "F7F2E6", dark: "F5EEDC")
    static let heroTextMuted = Color.adaptive(light: "D9CFB4", dark: "CDBF9C")

    // MARK: Gold

    /// Gold that sits on the indigo hero. Light `#C8A867`, dark `#D6BC85`.
    static let brandGold = Color.adaptive(light: "C8A867", dark: "D6BC85")
    static let goldStart = Color.adaptive(light: "E4D2A1", dark: "E4D2A1")
    static let goldEnd = Color.brandGold
    /// Espresso text on a gold chip. Same in both themes (`goldOnGold`).
    static let goldOnGold = Color(hex: "1D1708")

    static let successContainer = Color.adaptive(light: "E5EDE8", dark: "1B2C25")
    static let warningContainer = Color.adaptive(light: "F3EADD", dark: "33261C")
    static let dangerContainer = Color.adaptive(light: "F4E4E4", dark: "382127")
}

/// Hero wash used by the week card, settings header and the widget.
struct HeroGradient: View {
    var body: some View {
        LinearGradient(
            colors: [Color.heroStart, Color.heroEnd],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
