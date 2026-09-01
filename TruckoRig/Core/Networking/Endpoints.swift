import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// One backend call: path, method and optional JSON body.
struct Endpoint {
    var path: String
    var method: HTTPMethod = .get
    var body: Data?
    var query: [URLQueryItem] = []
    /// Endpoints that must not carry the account token (sign-in, refresh).
    var requiresAuth: Bool = true

    static func json<Body: Encodable>(
        _ path: String,
        method: HTTPMethod,
        body: Body,
        requiresAuth: Bool = true
    ) -> Endpoint {
        Endpoint(
            path: path,
            method: method,
            body: try? JSONEncoder.api.encode(body),
            requiresAuth: requiresAuth
        )
    }
}

/// Every backend route, versioned under `/v1`.
enum Endpoints {

    // MARK: - Auth

    static func signInWithApple(identityToken: String, fullName: String?) -> Endpoint {
        .json(
            "/v1/auth/apple",
            method: .post,
            body: AppleSignInRequest(identityToken: identityToken, fullName: fullName),
            requiresAuth: false
        )
    }

    static func signInWithEmail(email: String, password: String) -> Endpoint {
        .json(
            "/v1/auth/sign-in",
            method: .post,
            body: EmailCredentials(email: email, password: password),
            requiresAuth: false
        )
    }

    static func signUpWithEmail(email: String, password: String) -> Endpoint {
        .json(
            "/v1/auth/sign-up",
            method: .post,
            body: EmailCredentials(email: email, password: password),
            requiresAuth: false
        )
    }

    static func refresh(refreshToken: String) -> Endpoint {
        .json(
            "/v1/auth/refresh",
            method: .post,
            body: RefreshRequest(refreshToken: refreshToken),
            requiresAuth: false
        )
    }

    // MARK: - Sync

    static let fetchSnapshot = Endpoint(path: "/v1/sync/snapshot", method: .get)

    static func pushSnapshot(_ snapshot: AccountCloudSnapshot) -> Endpoint {
        .json("/v1/sync/snapshot", method: .put, body: snapshot)
    }

    static let fetchCursor = Endpoint(path: "/v1/sync/cursor", method: .get)

    static func pushCursor(_ cursor: SyncCursor) -> Endpoint {
        .json("/v1/sync/cursor", method: .put, body: cursor)
    }

    // MARK: - Devices

    static func registerDevice(deviceId: String) -> Endpoint {
        .json("/v1/devices/register", method: .post, body: DeviceRegistration(deviceId: deviceId))
    }

    static func updatePushToken(deviceId: String, token: String) -> Endpoint {
        .json("/v1/devices/push-token", method: .put, body: PushTokenUpdate(deviceId: deviceId, token: token))
    }

    // MARK: - Media

    static func mediaUploadURL(_ request: MediaUploadRequest) -> Endpoint {
        .json("/v1/media/upload-url", method: .post, body: request)
    }

    static func mediaComplete(_ request: MediaCompleteRequest) -> Endpoint {
        .json("/v1/media/complete", method: .post, body: request)
    }
}

extension JSONEncoder {
    /// Backend contract: ISO-8601 dates, snake_case keys.
    static let api: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
