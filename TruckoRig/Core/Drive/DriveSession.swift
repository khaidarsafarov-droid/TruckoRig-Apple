import Foundation
import UIKit
import GoogleSignIn

/// URLSession transport for Drive REST v3. Timeouts are one 60 second budget.
/// Android OkHttp uses 20/60/60; a timeout or a dropped connection is worded so the same
/// retry rule (`timeout`, `connection`, `unable to resolve`, `failed`) matches.
final class DriveURLSessionTransport: DriveTransport {
    private let session: URLSession

    init(session: URLSession = DriveURLSessionTransport.makeSession()) {
        self.session = session
    }

    func send(_ request: DriveHTTPRequest) throws -> DriveHTTPResponse {
        guard let url = URL(string: request.url) else {
            throw DriveFailure.api("List failed (0): bad url")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        for (header, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }
        if let body = request.body {
            urlRequest.httpBody = Data(body.utf8)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var output: Result<DriveHTTPResponse, DriveFailure> = .failure(.io("failed"))
        let task = session.dataTask(with: urlRequest) { data, response, error in
            if let error = error as NSError? {
                output = .failure(.io(Self.retryWord(error)))
            } else if let http = response as? HTTPURLResponse {
                let text = String(data: data ?? Data(), encoding: .utf8) ?? ""
                output = .success(DriveHTTPResponse(status: http.statusCode, body: text))
            } else {
                output = .failure(.io("failed"))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return try output.get()
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private static func retryWord(_ error: NSError) -> String {
        switch error.code {
        case NSURLErrorTimedOut:
            return "timeout"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "unable to resolve"
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost:
            return "connection"
        default:
            return "failed"
        }
    }
}

enum DrivePresenter {
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let root = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}

/// Google Sign-In for iOS. The only Drive scope requested is `drive.appdata`.
/// The SDK still adds the identity scopes, matching Android `DEFAULT_SIGN_IN` + `requestEmail`.
final class GoogleDriveAccount: DriveAccountSession {
    private let clientID: String

    init(clientID: String) {
        self.clientID = clientID
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    var email: String? {
        let value = GIDSignIn.sharedInstance.currentUser?.profile?.email
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasDriveScope: Bool {
        GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(DriveSchedule.driveAppDataScope) == true
    }

    func signIn(requestDriveScope: Bool, hint: String?) async -> DriveParsedSignIn {
        guard let presenter = DrivePresenter.topViewController() else {
            return DriveParsedSignIn(statusCode: DriveConnectInterpreter.statusDeveloperError, result: .canceled)
        }
        let user = GIDSignIn.sharedInstance.currentUser
        if requestDriveScope, let user {
            return await addScopes(user: user, presenter: presenter)
        }
        return await signIn(presenter: presenter, hint: hint, requestDriveScope: requestDriveScope)
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func restore() async {
        guard GIDSignIn.sharedInstance.currentUser == nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { _, _ in
                continuation.resume()
            }
        }
    }

    func accessToken() async -> String? {
        if GIDSignIn.sharedInstance.currentUser == nil {
            await restore()
        }
        guard let user = GIDSignIn.sharedInstance.currentUser else { return nil }
        return await withCheckedContinuation { continuation in
            user.refreshTokensIfNeeded { refreshed, _ in
                continuation.resume(returning: refreshed?.accessToken.tokenString)
            }
        }
    }

    private func signIn(
        presenter: UIViewController,
        hint: String?,
        requestDriveScope: Bool
    ) async -> DriveParsedSignIn {
        let scopes = requestDriveScope ? [DriveSchedule.driveAppDataScope] : nil
        return await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: hint,
                additionalScopes: scopes
            ) { result, error in
                continuation.resume(returning: Self.parse(result: result, error: error, requestedScope: requestDriveScope))
            }
        }
    }

    private func addScopes(user: GIDGoogleUser, presenter: UIViewController) async -> DriveParsedSignIn {
        await withCheckedContinuation { continuation in
            user.addScopes([DriveSchedule.driveAppDataScope], presenting: presenter) { result, error in
                continuation.resume(returning: Self.parse(result: result, error: error, requestedScope: true))
            }
        }
    }

    private static func parse(result: GIDSignInResult?, error: Error?, requestedScope: Bool) -> DriveParsedSignIn {
        if let error = error as NSError? {
            if error.code == GIDSignInError.Code.canceled.rawValue {
                return DriveParsedSignIn(statusCode: DriveConnectInterpreter.signInCancelled, result: .canceled)
            }
            if error.code == GIDSignInError.Code.scopesAlreadyGranted.rawValue && requestedScope {
                let email = result?.user.profile?.email ?? GIDSignIn.sharedInstance.currentUser?.profile?.email
                return DriveParsedSignIn(email: email, grantedDriveScope: true, result: .ok)
            }
            return DriveParsedSignIn(statusCode: DriveConnectInterpreter.statusDeveloperError, result: .canceled)
        }
        let user = result?.user
        let email = user?.profile?.email
        let granted = user?.grantedScopes?.contains(DriveSchedule.driveAppDataScope) == true
        return DriveParsedSignIn(email: email, grantedDriveScope: granted, result: .ok)
    }
}

enum DriveSignInCallback {
    /// Returns true when Google Sign-In consumed the URL. `truckorig://` falls through.
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
