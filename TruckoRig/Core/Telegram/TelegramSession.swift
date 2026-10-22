import Foundation

/// Device calls to `api.telegram.org`. No other host is used.
final class TelegramSession: @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TelegramBotAPI.readTimeout
        configuration.timeoutIntervalForResource = TelegramBotAPI.readTimeout
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func send(_ request: TelegramHTTPRequest) async throws -> TelegramHTTPResponse {
        guard let url = URL(string: request.url) else {
            throw TelegramSessionError.badURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if let body = request.body {
            urlRequest.httpBody = Data(body.utf8)
        }
        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return TelegramHTTPResponse(status: status, body: String(decoding: data, as: UTF8.self))
    }

    func download(token: String, fileId: String) async throws -> Data {
        let info = try await send(TelegramBotAPI.getFile(token: token, fileId: fileId))
        if let error = TelegramBotAPI.requireOK(method: "getFile", status: info.status, body: info.body) {
            throw TelegramSessionError.api(error)
        }
        let declared = TelegramBotAPI.declaredFileSize(from: info.body)
        if declared > TelegramBotAPI.maxDownloadBytes {
            throw TelegramSessionError.tooLarge
        }
        guard let path = TelegramBotAPI.filePath(from: info.body), let url = URL(string: TelegramBotAPI.fileURL(token: token, path: path)) else {
            throw TelegramSessionError.api(TelegramRedactor.redact("No file_path in response"))
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw TelegramSessionError.api(TelegramRedactor.redact("download failed: \(status)"))
        }
        if data.count > TelegramBotAPI.maxDownloadBytes { throw TelegramSessionError.tooLarge }
        return data
    }

    func setProfilePhoto(token: String, jpeg: Data) async -> Bool {
        let boundary = "TruckoRig\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"photo\"\r\n\r\n")
        append(TelegramBranding.profilePhotoAttachJSON)
        append("\r\n--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"logo\"; filename=\"logo.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        append("\r\n--\(boundary)--\r\n")
        guard let url = URL(string: TelegramBotAPI.root(token) + "/setMyProfilePhoto") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 20
        guard let (data, response) = try? await session.data(for: request) else { return false }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        return TelegramBotAPI.requireOK(method: "setMyProfilePhoto", status: status, body: text) == nil
    }
}

enum TelegramSessionError: Error {
    case badURL
    case api(String)
    case tooLarge
}
