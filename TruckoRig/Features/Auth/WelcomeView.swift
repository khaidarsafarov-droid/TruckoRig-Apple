import AuthenticationServices
import SwiftUI

/// Login wall. Three ways in: Apple, email, or no account at all.
struct WelcomeView: View {

    @Environment(AppState.self) private var appState
    @State private var isShowingEmailForm = false

    var body: some View {
        @Bindable var auth = appState.auth

        VStack(spacing: Spacing.section) {
            Spacer()

            VStack(spacing: Spacing.tight) {
                Image(systemName: "truck.box.badge.clock")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.forestPrimary)
                Text("app.name")
                    .font(.appLargeTitle)
                    .foregroundStyle(Color.forestText)
                Text("welcome.tagline")
                    .font(.appCallout)
                    .foregroundStyle(Color.forestTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: Spacing.standard) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task { await appState.auth.completeAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.controlRadius, style: .continuous))
                .accessibilityLabel("auth.apple")

                SoftButton(title: "auth.email", systemImage: "envelope", role: .secondary) {
                    isShowingEmailForm = true
                }

                Button("welcome.localMode") {
                    appState.auth.continueLocally()
                }
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestPrimary)

                Text("welcome.localMode.hint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.section)
            .padding(.bottom, Spacing.section)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .forestBackground()
        .sheet(isPresented: $isShowingEmailForm) {
            LoginView()
        }
        .alert(
            "auth.error.title",
            isPresented: .isPresented($auth.errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(auth.errorMessage ?? "") }
        )
        .loadingOverlay(appState.auth.isAuthenticating, message: "auth.signingIn")
    }
}

#Preview {
    PreviewHost {
        WelcomeView()
    }
}
