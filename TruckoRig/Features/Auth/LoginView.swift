import SwiftUI

/// Email sign-in and registration.
struct LoginView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: EmailAuthViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    form(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(viewModel?.mode.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = EmailAuthViewModel(auth: appState.auth)
            }
        }
        .onChange(of: appState.auth.session) {
            if appState.auth.isSignedIn { dismiss() }
        }
    }

    private func form(_ viewModel: EmailAuthViewModel) -> some View {
        @Bindable var model = viewModel

        return Form {
            Section {
                Picker("auth.mode", selection: $model.mode) {
                    ForEach(EmailAuthViewModel.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                SoftTextField(
                    title: "auth.emailAddress",
                    text: $model.email,
                    placeholder: "driver@example.com",
                    keyboard: .emailAddress,
                    autocapitalization: .never
                )
                SoftTextField(title: "auth.password", text: $model.password, isSecure: true)
                if viewModel.mode == .signUp {
                    SoftTextField(title: "auth.confirmPassword", text: $model.confirmPassword, isSecure: true)
                }
                if let message = viewModel.validationMessage {
                    Text(message)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
            } footer: {
                Text("auth.password.rule")
                    .font(.appCaption)
            }

            Section {
                SoftButton(title: viewModel.mode.title, isLoading: viewModel.isSubmitting) {
                    Task { await viewModel.submit() }
                }
                .disabled(!viewModel.canSubmit)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if appState.settings.resolvedBackendURL == nil {
                Section {
                    Label("auth.error.backendRequired", systemImage: "exclamationmark.triangle")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestWarning)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .forestBackground()
    }
}

#Preview {
    PreviewHost {
        LoginView()
    }
}
