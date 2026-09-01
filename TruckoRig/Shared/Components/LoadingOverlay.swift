import SwiftUI

/// Blocking progress overlay for operations the driver must wait on (import, restore, upload).
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

/// Inline banner shown when local changes are waiting to reach the server.
struct PendingSyncBanner: View {
    let pendingCount: Int

    var body: some View {
        if pendingCount > 0 {
            HStack(spacing: Spacing.tight) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("sync.pending \(pendingCount)")
                    .font(.appCaption)
            }
            .foregroundStyle(Color.forestTextSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.forestSurfaceMuted, in: Capsule())
        }
    }
}

#Preview {
    VStack {
        PendingSyncBanner(pendingCount: 3)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .forestBackground()
    .loadingOverlay(true, message: "status.syncing")
}
