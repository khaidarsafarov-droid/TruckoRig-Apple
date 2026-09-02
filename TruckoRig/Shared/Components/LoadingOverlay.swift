import SwiftUI

/// Blocking progress overlay for operations the driver must wait on (import, restore).
struct LoadingOverlay: View {
    var message: LocalizedStringKey = "status.working"

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: Spacing.standard) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.appCallout)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            .padding(Spacing.section)
            .background(Color.forestCard, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
            .softShadow()
        }
        .transition(.opacity)
        .accessibilityLabel(message)
    }
}

extension View {
    /// Shows `LoadingOverlay` above the view while `isPresented`.
    func loadingOverlay(_ isPresented: Bool, message: LocalizedStringKey = "status.working") -> some View {
        overlay {
            if isPresented { LoadingOverlay(message: message) }
        }
        .animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}

#Preview {
    Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forestBackground()
        .loadingOverlay(true, message: "status.working")
}
