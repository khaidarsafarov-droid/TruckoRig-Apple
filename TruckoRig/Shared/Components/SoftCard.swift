import SwiftUI

/// Standard white card used across every screen.
struct SoftCard<Content: View>: View {
    var padding: CGFloat = Spacing.standard
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            content
        }
        .softCard(padding: padding)
    }
}

/// Small titled block above a group of rows.
struct SectionHeader: View {
    let title: LocalizedStringKey
    var action: (() -> Void)?
    var actionTitle: LocalizedStringKey = "action.seeAll"

    var body: some View {
        HStack {
            Text(title)
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)
            Spacer()
            if let action {
                Button(actionTitle, action: action)
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.forestPrimary)
            }
        }
    }
}

/// One labelled figure — gross, miles, RPM.
struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var caption: String?
    var tint: Color = .forestText

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Text(value)
                .font(.appNumber)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let caption {
                Text(caption)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Placeholder shown when a list has nothing in it yet.
struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.standard) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(Color.forestAccent)
            Text(title)
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)
            Text(message)
                .font(.appCallout)
                .foregroundStyle(Color.forestTextSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.softPrimary)
                    .padding(.horizontal, 40)
            }
        }
        .padding(Spacing.section)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: Spacing.section) {
        SoftCard {
            SectionHeader(title: "screen.analytics")
            HStack {
                StatTile(title: "stat.gross", value: "$6,240")
                StatTile(title: "stat.miles", value: "2,410 mi")
                StatTile(title: "stat.rpm", value: "$2.59", tint: .forestSuccess)
            }
        }
        EmptyStateView(
            systemImage: "tray",
            title: "journal.empty.title",
            message: "journal.empty.message",
            actionTitle: "journal.addLoad",
            action: {}
        )
        .softCard()
    }
    .padding()
    .forestBackground()
}
