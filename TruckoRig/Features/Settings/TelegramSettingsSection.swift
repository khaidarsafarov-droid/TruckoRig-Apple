import SwiftUI
import UIKit

/// Telegram bot block on Settings. The token is entered in a sheet and kept in the Keychain.
struct TelegramSettingsSection: View {
    @Environment(AppState.self) private var appState
    @State private var showTokenDialog = false
    @State private var showPaywall = false

    var body: some View {
        let telegram = appState.telegram
        Section("settings.telegram.title") {
            Text("settings.telegram.desc")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            if !appState.premium.isActive {
                Text("premium.locked.telegram")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                Button("premium.subscribe") { showPaywall = true }
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(telegram.listening ? Color.forestPrimary : Color.forestTextSecondary)
                        .frame(width: 8, height: 8)
                    Text(telegram.listening ? "settings.telegram.active" : "settings.telegram.inactive")
                        .font(.appCaption)
                        .foregroundStyle(telegram.listening ? Color.forestPrimary : Color.forestTextSecondary)
                }
                Text(telegram.hasToken ? "settings.telegram.configured" : "settings.telegram.missing")
                    .font(.appCaption)
                    .foregroundStyle(telegram.hasToken ? Color.forestPrimary : Color.forestTextSecondary)
                if telegram.hasToken {
                    Button("settings.telegram.test") { Task { await telegram.testToken() } }
                        .disabled(telegram.busy)
                    Button("settings.telegram.change") { showTokenDialog = true }
                        .disabled(telegram.busy)
                    if telegram.paired {
                        Text("settings.telegram.paired")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestPrimary)
                        Button("settings.telegram.unpair") { telegram.unpair() }
                    } else {
                        Text("settings.telegram.pairHint \(telegram.pairingCode)")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                        if telegram.username != nil {
                            Button("settings.telegram.openBot") { open(telegram.openBotURL()) }
                        }
                    }
                } else {
                    Button("settings.telegram.add") { showTokenDialog = true }
                        .disabled(telegram.busy)
                    Button("onboard.telegram.botfather") { TelegramLinks.openBotFather() }
                }
                if telegram.busy { ProgressView() }
                if let status = telegram.statusMessage, !status.isEmpty {
                    Text(status)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
            }
        }
        .task {
            telegram.refresh()
            await telegram.refreshUsername()
        }
        .sheet(isPresented: $showTokenDialog) {
            TelegramTokenSheet(onClose: { showTokenDialog = false })
                .environment(appState)
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallSheet(onClose: { showPaywall = false })
                .environment(appState)
        }
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}

/// Add or change the BotFather token. The saved value is not shown again on the settings row.
struct TelegramTokenSheet: View {
    @Environment(AppState.self) private var appState
    var onClose: () -> Void

    @State private var token = ""
    @State private var revealed = false
    @State private var errorMessage: String?
    @FocusState private var focus: String?

    private var focusBinding: Binding<String?> {
        Binding(get: { focus }, set: { focus = $0 })
    }

    var body: some View {
        NavigationStack {
            KeyboardAvoidingScroll(focus: $focus) {
            VStack(alignment: .leading, spacing: Spacing.standard) {
                Text("settings.telegram.dialogHint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                SoftTextField(
                    title: "settings.telegram.tokenLabel",
                    text: $token,
                    placeholder: "settings.telegram.placeholder",
                    isSecure: !revealed,
                    autocapitalization: .never
                )
                .keyboardFocus(KeyboardField.telegramToken, in: focusBinding)
                Button(revealed ? "settings.telegram.hide" : "settings.telegram.show") {
                    revealed.toggle()
                }
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestPrimary)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
                if appState.telegram.busy { ProgressView("settings.telegram.checking") }
                Spacer()
            }
            .padding(Spacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .forestBackground()
            .navigationTitle("settings.telegram.dialogTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { onClose() }
                        .disabled(appState.telegram.busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(appState.telegram.busy ? "settings.telegram.checking" : "action.save") {
                        Task { await save() }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.telegram.busy)
                }
            }
        }
    }

    private func save() async {
        errorMessage = await appState.telegram.saveToken(token)
        if errorMessage == nil {
            token = ""
            onClose()
        }
    }
}

enum TelegramLinks {
    static let botFatherApp = URL(string: "tg://resolve?domain=BotFather")
    static let botFatherWeb = URL(string: "https://t.me/BotFather")

    static func openBotFather() {
        if let botFatherApp, UIApplication.shared.canOpenURL(botFatherApp) {
            UIApplication.shared.open(botFatherApp)
        } else if let botFatherWeb {
            UIApplication.shared.open(botFatherWeb)
        }
    }
}
