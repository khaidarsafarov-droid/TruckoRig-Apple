import SwiftUI

/// First launch: name, the kind of work, then an optional Telegram bot.
struct OnboardingView: View {

    @Environment(AppState.self) private var appState
    @State private var step = 0
    @State private var givenName = ""
    @State private var familyName = ""
    @State private var role = DriverRole.ownerOperator
    @State private var token = ""
    @State private var revealed = false
    @State private var errorMessage: String?
    @FocusState private var focus: String?

    private var canContinueName: Bool {
        !givenName.trimmed.isEmpty && !familyName.trimmed.isEmpty
    }

    var body: some View {
        NavigationStack {
            KeyboardAvoidingScroll(focus: $focus) {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    if step == 0 {
                        nameStep
                    } else if step == 1 {
                        roleStep
                    } else {
                        telegramStep
                    }
                }
                .padding(Spacing.section)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .forestBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: step) { _, _ in
                focus = nil
                KeyboardDismissal.resign()
            }
        }
    }

    private var focusBinding: Binding<String?> {
        Binding(get: { focus }, set: { focus = $0 })
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            Text("onboard.nameHint")
                .font(.appBody)
                .foregroundStyle(Color.forestTextSecondary)
            SoftTextField(title: "onboard.givenName", text: $givenName, autocapitalization: .words)
                .keyboardFocus(KeyboardField.givenName, in: focusBinding)
            SoftTextField(title: "onboard.familyName", text: $familyName, autocapitalization: .words)
                .keyboardFocus(KeyboardField.familyName, in: focusBinding)
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
                step = 2
            }
        }
    }

    private var telegramStep: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            Text("onboard.telegram.subtitle")
                .font(.appBody)
                .foregroundStyle(Color.forestTextSecondary)
            Text("onboard.telegram.steps")
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestText)
            Text("onboard.telegram.step1")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Text("onboard.telegram.step2")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Text("onboard.telegram.step3")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Text("onboard.telegram.step4")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Button("onboard.telegram.botfather") { TelegramLinks.openBotFather() }
                .font(.appBodyMedium)
                .foregroundStyle(Color.forestPrimary)
            SoftTextField(
                title: "settings.telegram.tokenLabel",
                text: $token,
                placeholder: "settings.telegram.placeholder",
                isSecure: !revealed,
                autocapitalization: .never
            )
            .keyboardFocus(KeyboardField.telegramToken, in: focusBinding)
            Button(revealed ? "settings.telegram.hide" : "settings.telegram.show") { revealed.toggle() }
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestPrimary)
            if let errorMessage {
                Text(errorMessage)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestError)
            }
            if appState.telegram.busy { ProgressView("settings.telegram.checking") }
            SoftButton(title: "onboard.telegram.save") {
                Task { await saveToken() }
            }
            .disabled(appState.telegram.busy)
            Button("onboard.telegram.skip") { finish(name: enteredName) }
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestTextSecondary)
                .disabled(appState.telegram.busy)
            Text("onboard.telegram.skipHint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private var title: LocalizedStringKey {
        switch step {
        case 0: return "onboard.title"
        case 1: return "onboard.roleTitle"
        default: return "onboard.telegram.title"
        }
    }

    private var enteredName: String? {
        let name = [givenName.trimmed, familyName.trimmed].filter { !$0.isEmpty }.joined(separator: " ")
        return name.nonEmpty
    }

    private func saveToken() async {
        if let error = await appState.telegram.saveToken(token) {
            errorMessage = error
            return
        }
        finish(name: enteredName)
    }

    private func finish(name: String?) {
        let profile = appState.catalog.profile ?? DriverProfile(
            preferredLanguage: appState.settings.language,
            weeklyGoal: appState.settings.weeklyGoal
        )
        if let name {
            profile.name = name
        }
        if step >= 1 {
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
