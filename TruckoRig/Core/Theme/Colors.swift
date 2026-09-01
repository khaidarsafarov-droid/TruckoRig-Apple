import SwiftUI

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
    /// Dark mode is not a tint of the light palette — the forest greens have to lift off a dark
    /// background instead of sinking into it — so each token names both variants explicitly.
    static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

/// "Mindwell Forest" palette.
extension Color {
    static let forestPrimary = Color.adaptive(light: "2D5A3D", dark: "6FA97F")
    static let forestSecondary = Color.adaptive(light: "4A7C59", dark: "5E9670")
    static let forestAccent = Color.adaptive(light: "7FB069", dark: "8FC77A")

    static let forestBackground = Color.adaptive(light: "F5F7F5", dark: "12160F")
    static let forestCard = Color.adaptive(light: "FFFFFF", dark: "1C2119")
    static let forestSurfaceMuted = Color.adaptive(light: "EDF1ED", dark: "252B22")

    static let forestText = Color.adaptive(light: "1A1A1A", dark: "F2F4F1")
    static let forestTextSecondary = Color.adaptive(light: "6B7280", dark: "A0A99C")
    static let forestSeparator = Color.adaptive(light: "E3E8E3", dark: "2E352B")

    static let forestSuccess = Color.adaptive(light: "22C55E", dark: "45D97C")
    static let forestWarning = Color.adaptive(light: "EAB308", dark: "F2C333")
    static let forestError = Color.adaptive(light: "EF4444", dark: "F87171")

    static let forestOnPrimary = Color.adaptive(light: "FFFFFF", dark: "0E1210")
}
