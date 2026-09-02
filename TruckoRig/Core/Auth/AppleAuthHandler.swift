import AuthenticationServices
import Foundation

/// What Sign in with Apple hands back.
struct AppleCredential {
    var userId: String
    var email: String?
    var fullName: String?
}

enum AppleAuthError: Error, LocalizedError {
    case missingCredential

    var errorDescription: String? {
        String(localized: "auth.error.appleCredential")
    }
}

/// Translates Sign in with Apple results and checks whether a stored account is still valid.
enum AppleAuthHandler {

    /// Translates a completed authorization from `SignInWithAppleButton`.
    static func credential(from authorization: ASAuthorization) throws -> AppleCredential {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleAuthError.missingCredential
        }
        return credential(from: appleCredential)
    }

    static func credential(from appleCredential: ASAuthorizationAppleIDCredential) -> AppleCredential {
        let name = [appleCredential.fullName?.givenName, appleCredential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        return AppleCredential(
            userId: appleCredential.user,
            email: appleCredential.email,
            fullName: name.isEmpty ? nil : name
        )
    }

    /// Whether Apple still considers the stored account authorized.
    ///
    /// A revoked account has to be signed out locally, otherwise the app keeps a database open for
    /// an identity the driver removed in Settings.
    static func isStillAuthorized(userId: String) async -> Bool {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userId) { state, _ in
                continuation.resume(returning: state == .authorized)
            }
        }
    }
}
