import SwiftUI

/// How domain verdicts are shown. Shared by the app and the widget, so a status looks the same on
/// the goal screen and on the home screen.
extension PaceStatus {
    var tint: Color {
        // Android `SemanticPalette.pace`: met and ahead are success, on-track is warning,
        // behind is danger.
        switch self {
        case .goalMet, .ahead: return .forestSuccess
        case .onTrack: return .forestWarning
        case .behind: return .forestError
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .goalMet: return "goal.status.met"
        case .ahead: return "goal.status.ahead"
        case .onTrack: return "goal.status.onTrack"
        case .behind: return "goal.status.behind"
        }
    }

    var systemImage: String {
        switch self {
        case .goalMet: return "checkmark.seal.fill"
        case .ahead: return "arrow.up.right.circle.fill"
        case .onTrack: return "equal.circle.fill"
        case .behind: return "arrow.down.right.circle.fill"
        }
    }
}

extension RPMBand {
    var tint: Color {
        switch self {
        case .good: return .forestSuccess
        case .acceptable: return .forestWarning
        case .low: return .forestError
        case .unknown: return .forestTextSecondary
        }
    }
}
