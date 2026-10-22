import Foundation

/// Android `DriveConnectOutcome`.
public enum DriveConnectOutcome: Equatable, Sendable {
    case granted
    case requestDriveConsent(email: String)
    case retryBackup
    case cancelled
    case failed
}

/// Android `DriveConnectPending`.
public enum DriveConnectPending: Equatable, Sendable {
    case none
    case accountPicker
    case driveConsent
    case tokenConsent
}

public enum DriveActivityResult: Equatable, Sendable {
    case ok
    case canceled
}

/// What a sign-in sheet returned. `statusCode` is the Play Services code Android inspects
/// (`12501` cancel, `16` CANCELED, `4` SIGN_IN_REQUIRED, `10` DEVELOPER_ERROR).
public struct DriveParsedSignIn: Equatable, Sendable {
    public var email: String?
    public var grantedDriveScope: Bool
    public var statusCode: Int?
    public var result: DriveActivityResult

    public init(
        email: String? = nil,
        grantedDriveScope: Bool = false,
        statusCode: Int? = nil,
        result: DriveActivityResult
    ) {
        self.email = email
        self.grantedDriveScope = grantedDriveScope
        self.statusCode = statusCode
        self.result = result
    }
}

/// Android `DriveConnectInterpreter`.
public enum DriveConnectInterpreter {
    public static let signInCancelled = 12_501
    public static let statusCanceled = 16
    public static let statusSignInRequired = 4
    public static let statusDeveloperError = 10

    public static func next(
        result: DriveActivityResult,
        email accountEmail: String?,
        grantedDriveScope: Bool,
        statusCode: Int?,
        pending: DriveConnectPending
    ) -> DriveConnectOutcome {
        if pending == .tokenConsent {
            return result == .ok ? .retryBackup : .cancelled
        }
        if result != .ok {
            if statusCode == nil || isUserCancel(statusCode) {
                return .cancelled
            }
            return .failed
        }
        let email = accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if grantedDriveScope && !email.isEmpty {
            return .granted
        }
        if !email.isEmpty && pending != .driveConsent {
            return .requestDriveConsent(email: email)
        }
        return .failed
    }

    public static func next(parsed: DriveParsedSignIn, pending: DriveConnectPending) -> DriveConnectOutcome {
        next(
            result: parsed.result,
            email: parsed.email,
            grantedDriveScope: parsed.grantedDriveScope,
            statusCode: parsed.statusCode,
            pending: pending
        )
    }

    /// Play Services cancel codes. A missing status is not a cancel; the caller treats a nil
    /// error together with a canceled result as a cancel.
    public static func isUserCancel(_ statusCode: Int?) -> Bool {
        guard let statusCode else { return false }
        return statusCode == signInCancelled
            || statusCode == statusCanceled
            || statusCode == statusSignInRequired
    }
}

/// The session the connect flow talks to. Google Sign-In on iOS implements this.
public protocol DriveAccountSession: AnyObject {
    var email: String? { get }
    var hasDriveScope: Bool { get }
    func signIn(requestDriveScope: Bool, hint: String?) async -> DriveParsedSignIn
    func signOut()
}

/// Android's two-step connect: identity first, then `drive.appdata` consent.
///
/// Combining the account picker with the restricted scope makes Play Services dismiss the
/// sheet. iOS can request the scope in one call, but the same sequence is kept so a signed-in
/// account without Drive still gets a second consent step instead of a loop.
public enum DriveConnectFlow {
    public static func connect(_ session: DriveAccountSession) async -> DriveConnectOutcome {
        let knownEmail = session.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if session.hasDriveScope && !knownEmail.isEmpty {
            return .granted
        }
        let pending: DriveConnectPending = knownEmail.isEmpty ? .accountPicker : .driveConsent
        let first = await session.signIn(
            requestDriveScope: pending == .driveConsent,
            hint: knownEmail.isEmpty ? nil : knownEmail
        )
        let outcome = DriveConnectInterpreter.next(parsed: first, pending: pending)
        guard case .requestDriveConsent(let email) = outcome else { return outcome }
        let second = await session.signIn(requestDriveScope: true, hint: email)
        return DriveConnectInterpreter.next(parsed: second, pending: .driveConsent)
    }
}
