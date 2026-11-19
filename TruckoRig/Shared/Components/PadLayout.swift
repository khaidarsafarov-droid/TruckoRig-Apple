import SwiftUI

private struct SuppressJournalSplitKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The iPad sidebar already provides the split. The journal then pushes a load instead of nesting another split.
    var suppressesJournalSplit: Bool {
        get { self[SuppressJournalSplitKey.self] }
        set { self[SuppressJournalSplitKey.self] = newValue }
    }
}

/// Keeps forms and lists from stretching across a 13-inch iPad. Compact phone layout is unchanged.
struct PadReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var size
    var maxWidth: CGFloat = 840

    func body(content: Content) -> some View {
        if size == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    func padReadable(maxWidth: CGFloat = 840) -> some View {
        modifier(PadReadableWidth(maxWidth: maxWidth))
    }

    /// iPad sheets stay a page, not a second full-screen app. iPhone covers stay full screen.
    func padOrPhoneCover<Cover: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder cover: @escaping () -> Cover
    ) -> some View {
        modifier(PadOrPhoneFlagCover(isPresented: isPresented, cover: cover))
    }
}

private struct PadOrPhoneFlagCover<Cover: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var size
    var isPresented: Binding<Bool>
    @ViewBuilder var cover: () -> Cover

    func body(content: Content) -> some View {
        if size == .regular {
            content.sheet(isPresented: isPresented, content: cover)
        } else {
            content.fullScreenCover(isPresented: isPresented, content: cover)
        }
    }
}
