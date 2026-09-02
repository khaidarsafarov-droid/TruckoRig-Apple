import AuthenticationServices
import Foundation
import Observation

/// Owns the signed-in identity.
///
/// Sign in with Apple scopes a local database to that Apple user. There is no remote account
/// server: everything stays on the phone (or in a JSON backup the driver exports).
@MainActor
@Observable
final class AuthManager {

    private(set) var session: AuthSession?
    private(set) var isAuthenticating = false
    var errorMessage: String?

    var isSignedIn: Bool { session != nil }

    init() {
        self.session = AuthSessionStore.load()
    }

    // MARK: - Sign in

    /// Completes the flow started by `SignInWithAppleButton`.
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        switch result {
        case .success(let authorization):
            do {
                try await adopt(AppleAuthHandler.credential(from: authorization))
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Continues without an account: everything stays on this phone.
    func continueLocally() {
        apply(session: .localSession)
    }

    // MARK: - Sign out

    func signOut() {
        session = nil
        AuthSessionStore.save(nil)
    }

    /// Signs out when Apple reports the account was revoked in system Settings.
    func verifyAppleCredentialIfNeeded() async {
        guard let session, session.provider == .apple else { return }
        guard await AppleAuthHandler.isStillAuthorized(userId: session.userId) == false else { return }
        AppLog.auth.notice("Apple credential revoked; signing out")
        signOut()
    }

    // MARK: - Internals

    private func adopt(_ credential: AppleCredential) async throws {
        var newSession = AuthSession(
            userId: credential.userId,
            provider: .apple,
            email: credential.email,
            displayName: credential.fullName,
            createdAt: Date()
        )
        // Apple only reveals the name on first authorization; keep whatever we already stored.
        if let existing = AuthSessionStore.load(), existing.userId == credential.userId {
            newSession.email = newSession.email ?? existing.email
            newSession.displayName = newSession.displayName ?? existing.displayName
            newSession.createdAt = existing.createdAt
        }
        apply(session: newSession)
    }

    private func apply(session: AuthSession) {
        self.session = session
        AuthSessionStore.save(session)
        errorMessage = nil
    }
}
