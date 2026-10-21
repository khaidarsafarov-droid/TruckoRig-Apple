import SwiftUI
import UIKit

/// DM Sans, with Roboto standing in for Cyrillic.
///
/// Android ships DM Sans, which has no Cyrillic glyphs, so Russian text there is drawn by Roboto.
/// iOS does not do that automatically for a bundled face: a missing glyph would fall through to
/// the system font. Each face below cascades to the matching Roboto weight first.
enum AppFont {

    enum Weight: String {
        case regular
        case medium
        case semibold
        case bold

        var dmSansName: String {
            switch self {
            case .regular: return "DMSans-Regular"
            case .medium: return "DMSans-Medium"
            case .semibold: return "DMSans-SemiBold"
            case .bold: return "DMSans-Bold"
            }
        }

        /// Roboto has no semibold master; Android's extra-bold also aliases to bold.
        var robotoName: String {
            switch self {
            case .regular: return "Roboto-Regular"
            case .medium, .semibold: return "Roboto-Medium"
            case .bold: return "Roboto-Bold"
            }
        }

        var systemWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }

        var uiWeight: UIFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    private static let availableFaces: Set<String> = Set(
        UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) }
    )

    static var isBundled: Bool {
        availableFaces.contains(Weight.regular.dmSansName)
    }

    /// DM Sans, then Roboto, then the system font. Dynamic Type scales it against `style`.
    static func font(_ weight: Weight, size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        let base = uiFont(weight, size: size)
        let metrics = UIFontMetrics(forTextStyle: style.uiTextStyle)
        return Font(metrics.scaledFont(for: base))
    }

    static func uiFont(_ weight: Weight, size: CGFloat) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight.uiWeight)
        guard let dmSans = UIFont(name: weight.dmSansName, size: size) else {
            return UIFont(name: weight.robotoName, size: size) ?? system
        }
        guard let roboto = UIFont(name: weight.robotoName, size: size) else {
            return dmSans
        }
        let descriptor = dmSans.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName.cascadeList: [roboto.fontDescriptor, system.fontDescriptor],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

extension Font {
    /// Android `Type.kt`: 32 bold for the screen title, 24 semibold for display-small.
    static var appLargeTitle: Font { AppFont.font(.bold, size: 32, relativeTo: .largeTitle) }
    static var appTitle: Font { AppFont.font(.semibold, size: 24, relativeTo: .title) }
    static var appHeadline: Font { AppFont.font(.semibold, size: 20, relativeTo: .headline) }
    static var appBody: Font { AppFont.font(.regular, size: 16, relativeTo: .body) }
    static var appBodyMedium: Font { AppFont.font(.medium, size: 16, relativeTo: .body) }
    static var appCallout: Font { AppFont.font(.regular, size: 14, relativeTo: .callout) }
    static var appCaption: Font { AppFont.font(.regular, size: 12, relativeTo: .caption) }
    static var appCaptionMedium: Font { AppFont.font(.medium, size: 12, relativeTo: .caption) }
    /// Tabular figures for money columns.
    static var appNumber: Font { AppFont.font(.bold, size: 20, relativeTo: .title3).monospacedDigit() }
    static var appNumberLarge: Font { AppFont.font(.bold, size: 32, relativeTo: .largeTitle).monospacedDigit() }
}
