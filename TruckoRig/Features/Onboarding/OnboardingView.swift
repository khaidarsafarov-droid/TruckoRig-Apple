import SwiftUI

/// First launch: name, then the kind of work. Telegram is a later stage and is not asked here.
struct OnboardingView: View {

    @Environment(AppState.self) private var appState
    @State private var step = 0
    @State private var givenName = ""
    @State private var familyName = ""
    @State private var role = DriverRole.ownerOperator
    @State private var errorMessage: String?

    private var canContinueName: Bool {
        !givenName.trimmed.isEmpty && !familyName.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.section) {
                if step == 0 {
                    nameStep
                } else {
                    roleStep
                }
                Spacer()
            }
            .padding(Spacing.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .forestBackground()
            .navigationTitle(step == 0 ? "onboard.title" : "onboard.roleTitle")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            Text("onboard.nameHint")
                .font(.appBody)
                .foregroundStyle(Color.forestTextSecondary)
            SoftTextField(title: "onboard.givenName", text: $givenName, autocapitalization: .words)
            SoftTextField(title: "onboard.familyName", text: $familyName, autocapitalization: .words)
            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestError)
            }
            SoftButton(title: "onboard.continue") {
                guard canContinueName else {
                    errorMessage = String(localized: "onboard.nameRequired")
                    return
                }
                errorMessage = nil
                step = 1
            }
            Button("onboard.skip") { finish(name: nil) }
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private var roleStep: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            Text("onboard.roleLabel")
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestTextSecondary)
            ForEach(DriverRole.allCases) { option in
                Button {
                    role = option
                } label: {
                    HStack {
                        Text(option.title)
                            .font(.appBodyMedium)
                            .foregroundStyle(Color.forestText)
                        Spacer()
                        if role == option {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.forestPrimary)
                        }
                    }
                    .padding(Spacing.standard)
                    .background(Color.forestCard, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            SoftButton(title: "onboard.next") {
                let name = [givenName.trimmed, familyName.trimmed].filter { !$0.isEmpty }.joined(separator: " ")
                finish(name: name.nonEmpty)
            }
        }
    }

    private func finish(name: String?) {
        let profile = appState.catalog.profile ?? DriverProfile(
            preferredLanguage: appState.settings.language,
            weeklyGoal: appState.settings.weeklyGoal
        )
        if let name {
            profile.name = name
        }
        if step == 1 {
            profile.role = role.rawValue
        }
        appState.saveProfile(profile)
        appState.settings.onboardingComplete = true
    }
}

enum DriverRole: String, CaseIterable, Identifiable {
    case ownerOperator
    case hiredDriver
    case dispatcher

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .ownerOperator: return "onboard.role.owner"
        case .hiredDriver: return "onboard.role.hired"
        case .dispatcher: return "onboard.role.dispatcher"
        }
    }
}
