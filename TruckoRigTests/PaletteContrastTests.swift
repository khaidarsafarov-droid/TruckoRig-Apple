import XCTest
@testable import TruckoRig

/// WCAG 2.1 relative luminance for the light cabin. The numbers are the contract for item 6.
final class PaletteContrastTests: XCTestCase {

    func testLightGoldInkClearsTextAndIconContrast() {
        let ink = ThemePalette.goldInkLight
        XCTAssertGreaterThanOrEqual(contrast(ink, ThemePalette.backgroundLight), 4.5, "text on the page")
        XCTAssertGreaterThanOrEqual(contrast(ink, ThemePalette.surfaceLight), 4.5, "text on a card")
        XCTAssertGreaterThanOrEqual(contrast(ink, ThemePalette.surfaceMutedLight), 4.5, "text on a muted wash")
        XCTAssertGreaterThanOrEqual(contrast(ink, ThemePalette.backgroundLight), 3.0, "icons on the page")
    }

    func testChampagneFillStaysTooLightForText() {
        let fill = ThemePalette.champagneLight
        XCTAssertLessThan(contrast(fill, ThemePalette.backgroundLight), 3.0)
        XCTAssertLessThan(contrast(fill, ThemePalette.surfaceLight), 3.0)
        XCTAssertNotEqual(fill, ThemePalette.goldInkLight)
    }

    func testDarkGoldAndLightBodyTextStayAboveAA() {
        XCTAssertGreaterThanOrEqual(contrast(ThemePalette.goldInkDark, ThemePalette.backgroundDark), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(ThemePalette.onGold, ThemePalette.goldInkDark), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(ThemePalette.onPrimaryLight, ThemePalette.accentLight), 4.5)

        let surfaces = [ThemePalette.backgroundLight, ThemePalette.surfaceLight, ThemePalette.surfaceMutedLight]
        let inks = [
            ThemePalette.textLight,
            ThemePalette.textSecondaryLight,
            ThemePalette.successLight,
            ThemePalette.warningLight,
            ThemePalette.errorLight,
        ]
        for ink in inks {
            for surface in surfaces {
                XCTAssertGreaterThanOrEqual(contrast(ink, surface), 4.5, "\(ink) on \(surface)")
            }
        }
    }

    /// WCAG 2.1 relative luminance, sRGB.
    private func contrast(_ hex: String, _ other: String) -> Double {
        let lighter = max(luminance(hex), luminance(other))
        let darker = min(luminance(hex), luminance(other))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(_ hex: String) -> Double {
        let value = UInt32(hex, radix: 16) ?? 0
        let red = channel(Double((value >> 16) & 0xFF) / 255)
        let green = channel(Double((value >> 8) & 0xFF) / 255)
        let blue = channel(Double(value & 0xFF) / 255)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func channel(_ component: Double) -> Double {
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }
}
