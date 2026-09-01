import Foundation
import Observation
import SwiftUI

/// Form state for email sign-in and registration.
@MainActor
@Observable
final class EmailAuthViewModel {

    enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .signIn: return "auth.signIn"
            case .signUp: return "auth.signUp"
            }
        }
    }

    var mode: Mode = .signIn
    var email = ""
    var password = ""
    var confirmPassword = ""
    var isSubmitting = false

    private let auth: AuthManager

    init(auth: AuthManager) {
        self.auth = auth
    }

    // MARK: - Validation

    private static let emailPattern = Rx(#"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"#)

    var isEmailValid: Bool { Self.emailPattern.containsMatch(in: email.trimmed) }

    /// Eight characters with at least one letter and one digit. Long enough to matter, loose
    /// enough to type on a phone in a truck stop.
    var isPasswordValid: Bool {
        password.count >= 8
            && password.rangeOfCharacter(from: .letters) != nil
            && password.rangeOfCharacter(from: .decimalDigits) != nil
    }

    var doPasswordsMatch: Bool {
        mode == .signIn || password == confirmPassword
    }

    var canSubmit: Bool {
        !isSubmitting && isEmailValid && isPasswordValid && doPasswordsMatch
    }

    /// Message for the field the driver most recently broke, or `nil` when the form is clean.
    var validationMessage: String? {
        if !email.isEmpty, !isEmailValid { return String(localized: "auth.error.email") }
        if !password.isEmpty, !isPasswordValid { return String(localized: "auth.error.password") }
        if !doPasswordsMatch { return String(localized: "auth.error.passwordMismatch") }
        return nil
    }

    // MARK: - Submit

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        switch mode {
        case .signIn:
            await auth.signInWithEmail(email: email.trimmed, password: password)
        case .signUp:
            await auth.signUpWithEmail(email: email.trimmed, password: password)
        }
        if auth.isSignedIn { clearSecrets() }
    }

    func toggleMode() {
        mode = mode == .signIn ? .signUp : .signIn
        confirmPassword = ""
    }

    private func clearSecrets() {
        password = ""
        confirmPassword = ""
    }
}
