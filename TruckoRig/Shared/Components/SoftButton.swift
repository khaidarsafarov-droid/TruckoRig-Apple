import SwiftUI

/// Primary action button with an optional icon and busy state.
struct SoftButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var isLoading = false
    var role: Role = .primary
    let action: () -> Void

    enum Role {
        case primary
        case secondary
        case destructive
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.tight) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(role == .secondary ? Color.forestPrimary : Color.forestOnPrimary)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
        }
        .disabled(isLoading)
        .modifier(StyleModifier(role: role))
        .accessibilityLabel(title)
    }

    private struct StyleModifier: ViewModifier {
        let role: Role

        func body(content: Content) -> some View {
            switch role {
            case .primary: content.buttonStyle(.softPrimary)
            case .secondary: content.buttonStyle(.softSecondary)
            case .destructive: content.buttonStyle(.softDestructive)
            }
        }
    }
}

/// Compact pill used for filters and week chips.
struct SoftChip: View {
    let title: String
    var isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appCaptionMedium)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.forestPrimary : Color.forestSurfaceMuted,
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.forestOnPrimary : Color.forestTextSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    VStack(spacing: Spacing.standard) {
        SoftButton(title: "journal.addLoad", systemImage: "plus", action: {})
        SoftButton(title: "action.save", isLoading: true, action: {})
        SoftButton(title: "action.cancel", role: .secondary, action: {})
        SoftButton(title: "action.delete", role: .destructive, action: {})
        HStack {
            SoftChip(title: "W32", isSelected: true, action: {})
            SoftChip(title: "W31", isSelected: false, action: {})
        }
    }
    .padding()
    .forestBackground()
}
