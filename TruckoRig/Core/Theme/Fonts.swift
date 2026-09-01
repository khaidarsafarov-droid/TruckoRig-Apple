import SwiftUI
import UIKit

/// DM Sans type scale.
///
/// The family is optional at runtime: if the TTFs are not bundled the app falls back to the system
/// font at the same size and weight rather than silently rendering nothing.
enum AppFont {

    enum Weight: String {
        case regular = "DMSans-Regular"
        case medium = "DMSans-Medium"
        case bold = "DMSans-Bold"

        var systemWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .bold: return .bold
            }
        }
    }

    private static let availableFamilies: Set<String> = Set(
        UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) }
    )

    static var isBundled: Bool {
        availableFamilies.contains(Weight.regular.rawValue)
    }

    /// Font that scales with Dynamic Type, relative to `style`.
    static func font(_ weight: Weight, size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        guard availableFamilies.contains(weight.rawValue) else {
            return .system(size: size, weight: weight.systemWeight).leading(.standard)
        }
        return .custom(weight.rawValue, size: size, relativeTo: style)
    }
}

extension Font {
    static var appLargeTitle: Font { AppFont.font(.bold, size: 32, relativeTo: .largeTitle) }
    static var appTitle: Font { AppFont.font(.bold, size: 24, relativeTo: .title) }
    static var appHeadline: Font { AppFont.font(.medium, size: 18, relativeTo: .headline) }
    static var appBody: Font { AppFont.font(.regular, size: 16, relativeTo: .body) }
    static var appBodyMedium: Font { AppFont.font(.medium, size: 16, relativeTo: .body) }
    static var appCallout: Font { AppFont.font(.regular, size: 15, relativeTo: .callout) }
    static var appCaption: Font { AppFont.font(.regular, size: 13, relativeTo: .caption) }
    static var appCaptionMedium: Font { AppFont.font(.medium, size: 13, relativeTo: .caption) }
    /// Tabular figures for money columns.
    static var appNumber: Font { AppFont.font(.bold, size: 20, relativeTo: .title3).monospacedDigit() }
    static var appNumberLarge: Font { AppFont.font(.bold, size: 34, relativeTo: .largeTitle).monospacedDigit() }
}
