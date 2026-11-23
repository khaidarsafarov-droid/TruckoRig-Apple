import SwiftUI

/// Compact Midnight & Gold sheet shown inside the system share panel.
struct ShareExtensionScreen: View {
    @Bindable var model: ShareExtensionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "truck.box.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.brandGold)
                Text("share.title")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.heroText)
                Spacer(minLength: 0)
            }

            Group {
                if model.phase == .checking {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.brandGold)
                        Text("share.checking")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.heroText)
                    }
                } else {
                    Text(message)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.heroText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if model.phase != .checking {
                VStack(spacing: 10) {
                    if showsOpen {
                        Button(action: model.openHost) {
                            Text("share.open")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.goldOnGold)
                        .background(
                            LinearGradient(colors: [Color.goldStart, Color.goldEnd], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    Button(action: model.finish) {
                        Text("share.done")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.heroText)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "0D0F1E"))
        .preferredColorScheme(.dark)
    }

    private var showsOpen: Bool {
        switch model.phase {
        case .added:
            return true
        case .duplicate:
            return true
        case .checking:
            return false
        case .rejected:
            return false
        case .unavailable:
            return false
        case .failed:
            return false
        }
    }

    private var message: LocalizedStringKey {
        switch model.phase {
        case .checking:
            return "share.checking"
        case .added(let partial, let many):
            if many { return "share.added.many" }
            return partial ? "share.added.partial" : "share.added"
        case .duplicate:
            return "share.duplicate"
        case .rejected:
            return "share.rejected"
        case .unavailable:
            return "share.unavailable"
        case .failed:
            return "share.failed"
        }
    }
}
