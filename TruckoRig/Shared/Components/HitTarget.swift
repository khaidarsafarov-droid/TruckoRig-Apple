import SwiftUI

extension View {
    /// Grows the tappable area to at least 44×44 pt. Whatever was drawn before this stays its size.
    func minimumHitTarget(_ side: CGFloat = 44) -> some View {
        frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
    }
}
