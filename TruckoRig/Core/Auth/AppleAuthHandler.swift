import AuthenticationServices
import Foundation
import UIKit

/// What Sign in with Apple hands back.
struct AppleCredential {
    var userId: String
    var identityToken: String?
    var email: String?
    var fullName: String?
}

enum AppleAuthError: Error, LocalizedError {
    case cancelled
    case missingCredential
    case failed(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled: return String(localized: "auth.error.cancelled")
        case .missingCredential: return String(localized: "auth.error.appleCredential")
        case .failed(let error): return error.localizedDescription
        }
    }
}

/// Bridges `AuthenticationServices` to async/await.
///
/// Apple only sends the name and email on the very first authorization for an app, so those are
/// captured here and persisted immediately; later sign-ins only carry the user identifier.
final class AppleAuthHandler: NSObject {

    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var controller: ASAuthorizationController?

    /// Starts an interactive authorization.
    func requestSignIn() async throws -> AppleCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    /// Translates a completed authorization (for example from `SignInWithAppleButton`).
    static func credential(from authorization: ASAuthorization) throws -> AppleCredential {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AppleAuthError.missingCredential
        }
        return credential(from: appleCredential)
    }

    static func credential(from appleCredential: ASAuthorizationAppleIDCredential) -> AppleCredential {
        let token = appleCredential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        let name = [appleCredential.fullName?.givenName, appleCredential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        return AppleCredential(
            userId: appleCredential.user,
            identityToken: token,
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

extension AppleAuthHandler: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { finish() }
        do {
            continuation?.resume(returning: try Self.credential(from: authorization))
        } catch {
            continuation?.resume(throwing: error)
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        defer { finish() }
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: AppleAuthError.cancelled)
        } else {
            continuation?.resume(throwing: AppleAuthError.failed(error))
        }
    }

    private func finish() {
        continuation = nil
        controller = nil
    }
}

extension AppleAuthHandler: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
