import AuthenticationServices
import Foundation
import Observation

/// Owns the signed-in identity and the tokens that go with it.
///
/// Sign in with Apple works with no backend at all: the Apple user identifier is enough to scope a
/// local database. Tokens are only fetched when the driver has configured cloud sync, so the app
/// is fully usable offline and account-isolated either way.
@MainActor
@Observable
final class AuthManager {

    private(set) var session: AuthSession?
    private(set) var isAuthenticating = false
    var errorMessage: String?

    private let settings: AppSettings
    private let appleHandler = AppleAuthHandler()
    private var cachedTokens: AuthTokens?

    var isSignedIn: Bool { session != nil }
    var isCloudAccount: Bool { session?.provider != .local && session != nil }

    init(settings: AppSettings) {
        self.settings = settings
        let restored = AuthSessionStore.load()
        self.session = restored
        if let userId = restored?.userId {
            self.cachedTokens = JWTStore.load(for: userId)
        }
    }

    // MARK: - Sign in

    /// Completes the flow started by `SignInWithAppleButton`.
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            do {
                try await adopt(AppleAuthHandler.credential(from: authorization))
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            // A cancel is a normal outcome, not something to shout about.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Starts Sign in with Apple programmatically (used for re-authentication).
    func signInWithApple() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            try await adopt(try await appleHandler.requestSignIn())
        } catch AppleAuthError.cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithEmail(email: String, password: String) async {
        await runEmailFlow { client in
            try await client.send(
                Endpoints.signInWithEmail(email: email, password: password),
                as: AuthResponse.self
            )
        }
    }

    func signUpWithEmail(email: String, password: String) async {
        await runEmailFlow { client in
            try await client.send(
                Endpoints.signUpWithEmail(email: email, password: password),
                as: AuthResponse.self
            )
        }
    }

    /// Continues without an account: everything stays on this phone.
    func continueLocally() {
        apply(session: .localSession, tokens: nil)
    }

    // MARK: - Sign out

    func signOut(eraseLocalData: Bool = false) {
        if let userId = session?.userId {
            JWTStore.delete(for: userId)
        }
        cachedTokens = nil
        session = nil
        AuthSessionStore.save(nil)
        if eraseLocalData {
            JWTStore.deleteAll()
        }
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

        var tokens: AuthTokens?
        if let identityToken = credential.identityToken, settings.resolvedBackendURL != nil {
            // A backend outage must not block sign-in: the driver can still work locally and sync
            // will pick up the exchange later.
            tokens = try? await exchangeAppleToken(identityToken, fullName: credential.fullName)
        }
        apply(session: newSession, tokens: tokens)
    }

    private func exchangeAppleToken(_ identityToken: String, fullName: String?) async throws -> AuthTokens? {
        guard let client = makeClient() else { return nil }
        let response = try await client.send(
            Endpoints.signInWithApple(identityToken: identityToken, fullName: fullName),
            as: AuthResponse.self
        )
        return AuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: response.expiresAt
        )
    }

    private func runEmailFlow(_ operation: (APIClient) async throws -> AuthResponse) async {
        guard let client = makeClient() else {
            errorMessage = String(localized: "auth.error.backendRequired")
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let response = try await operation(client)
            apply(
                session: AuthSession(
                    userId: response.userId,
                    provider: .email,
                    email: response.email,
                    displayName: response.displayName,
                    createdAt: Date()
                ),
                tokens: AuthTokens(
                    accessToken: response.accessToken,
                    refreshToken: response.refreshToken,
                    expiresAt: response.expiresAt
                )
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func apply(session: AuthSession, tokens: AuthTokens?) {
        self.session = session
        self.cachedTokens = tokens
        AuthSessionStore.save(session)
        if let tokens {
            JWTStore.save(tokens, for: session.userId)
        }
        errorMessage = nil
    }

    /// Client used for auth calls themselves; sync builds its own against the same base URL.
    private func makeClient() -> APIClient? {
        guard let baseURL = settings.resolvedBackendURL else { return nil }
        return APIClient(baseURL: baseURL, tokens: self)
    }
}

extension AuthManager: TokenSupplying {

    func currentTokens() async -> AuthTokens? {
        guard let tokens = cachedTokens, !tokens.isExpired() else {
            return await refreshTokens() ?? cachedTokens
        }
        return tokens
    }

    func refreshTokens() async -> AuthTokens? {
        guard let session,
              let refreshToken = cachedTokens?.refreshToken,
              let baseURL = settings.resolvedBackendURL
        else { return nil }

        // Deliberately a bare client: refreshing through the authenticating client would recurse.
        var request = URLRequest(url: baseURL.appendingPathComponent("/v1/auth/refresh"))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder.api.encode(RefreshRequest(refreshToken: refreshToken))

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder.api.decode(AuthResponse.self, from: data)
        else {
            AppLog.auth.notice("Token refresh failed")
            return nil
        }

        let tokens = AuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? refreshToken,
            expiresAt: decoded.expiresAt
        )
        cachedTokens = tokens
        JWTStore.save(tokens, for: session.userId)
        return tokens
    }
}
