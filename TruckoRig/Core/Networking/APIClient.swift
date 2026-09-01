import Foundation

enum APIError: Error, LocalizedError {
    case notConfigured
    case invalidResponse
    case unauthorized
    case server(status: Int, message: String?)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return String(localized: "sync.error.notConfigured")
        case .invalidResponse: return String(localized: "sync.error.invalidResponse")
        case .unauthorized: return String(localized: "sync.error.unauthorized")
        case .server(let status, let message): return message ?? String(localized: "sync.error.server \(status)")
        case .transport: return String(localized: "sync.error.offline")
        case .decoding: return String(localized: "sync.error.invalidResponse")
        }
    }
}

/// Supplies and refreshes the bearer token for outgoing requests.
protocol TokenSupplying: Sendable {
    func currentTokens() async -> AuthTokens?
    /// Exchanges the refresh token for a new pair. Returns `nil` when the session is gone.
    func refreshTokens() async -> AuthTokens?
}

/// URLSession wrapper for the TruckoRig backend.
///
/// An actor because token refresh must happen once: several screens can sync at the same moment
/// and a stampede of refreshes would invalidate each other's tokens.
actor APIClient {

    private let baseURL: URL
    private let session: URLSession
    private let tokens: TokenSupplying
    private var refreshTask: Task<AuthTokens?, Never>?

    init(baseURL: URL, tokens: TokenSupplying, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session
    }

    @discardableResult
    func send(_ endpoint: Endpoint) async throws -> Data {
        try await perform(endpoint, allowRefresh: true)
    }

    func send<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let data = try await perform(endpoint, allowRefresh: true)
        do {
            return try JSONDecoder.api.decode(type, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func perform(_ endpoint: Endpoint, allowRefresh: Bool) async throws -> Data {
        let request = try await makeRequest(endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401 where endpoint.requiresAuth && allowRefresh:
            guard await refreshOnce() != nil else { throw APIError.unauthorized }
            return try await perform(endpoint, allowRefresh: false)
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.server(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    private func makeRequest(_ endpoint: Endpoint) async throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.notConfigured }
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }
        guard let url = components.url else { throw APIError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if endpoint.requiresAuth, let token = await tokens.currentTokens()?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Coalesces concurrent refreshes into one.
    private func refreshOnce() async -> AuthTokens? {
        if let refreshTask { return await refreshTask.value }
        let task = Task { await tokens.refreshTokens() }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private static func errorMessage(from data: Data) -> String? {
        struct ServerError: Decodable {
            var message: String?
            var error: String?
        }
        guard let decoded = try? JSONDecoder.api.decode(ServerError.self, from: data) else { return nil }
        return decoded.message ?? decoded.error
    }
}
