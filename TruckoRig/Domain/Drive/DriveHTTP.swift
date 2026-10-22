import Foundation

/// One Drive REST call. The app sends it with URLSession; tests answer it from a script.
public struct DriveHTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: String?

    public init(method: String, url: String, headers: [String: String] = [:], body: String? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct DriveHTTPResponse: Equatable, Sendable {
    public var status: Int
    public var body: String

    public init(status: Int, body: String) {
        self.status = status
        self.body = body
    }
}

public protocol DriveTransport: AnyObject {
    func send(_ request: DriveHTTPRequest) throws -> DriveHTTPResponse
}

public struct DriveRemoteFile: Equatable, Sendable {
    public var id: String
    public var modifiedAt: Int64

    public init(id: String, modifiedAt: Int64) {
        self.id = id
        self.modifiedAt = modifiedAt
    }
}

public enum DriveFailure: Error, Equatable, Sendable {
    case notSignedIn
    case needsConsent
    case api(String)
    case io(String)
    case invalidJSON

    public var message: String {
        switch self {
        case .notSignedIn: return "Not signed in to Google Drive"
        case .needsConsent: return "consent"
        case .api(let text): return text
        case .io(let text): return text
        case .invalidJSON: return "Remote backup is not valid JSON"
        }
    }
}

public enum DriveHTTP {
    public static let filesRoot = "https://www.googleapis.com/drive/v3/files"
    public static let uploadRoot = "https://www.googleapis.com/upload/drive/v3/files"

    /// Java `URLEncoder.encode`: space becomes `+`, everything outside the unreserved set is `%HH`.
    public static func formEncode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            let scalar = Unicode.Scalar(byte)
            let unreserved = (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || scalar == "-"
                || scalar == "_"
                || scalar == "."
                || scalar == "*"
            if scalar == " " {
                out.append("+")
            } else if unreserved {
                out.append(Character(scalar))
            } else {
                out.append(String(format: "%%%02X", byte))
            }
        }
        return out
    }

    public static func listURL(fileName: String) -> String {
        let query = formEncode("name='\(fileName)' and trashed=false")
        return "\(filesRoot)?spaces=appDataFolder&q=\(query)&fields=files(id,name,modifiedTime)&pageSize=1"
    }

    public static func authorized(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)"]
    }

    /// Android `GoogleDriveApiClient.buildMultipartRelated`. No trailing CRLF after the closing boundary.
    public static func multipartRelated(boundary: String, metadataJSON: String, fileJSON: String) -> String {
        var body = ""
        body += "--\(boundary)\r\n"
        body += "Content-Type: application/json; charset=UTF-8\r\n\r\n"
        body += metadataJSON
        body += "\r\n"
        body += "--\(boundary)\r\n"
        body += "Content-Type: application/json; charset=UTF-8\r\n\r\n"
        body += fileJSON
        body += "\r\n"
        body += "--\(boundary)--"
        return body
    }

    public static func createMetadata(fileName: String) -> String {
        "{\"name\":\(DriveJSON.escape(fileName)),\"parents\":[\"appDataFolder\"]}"
    }

    /// Stored id wins when it is non-blank. Nil means create.
    public static func uploadFileID(stored: String?, listed: String?) -> String? {
        nonBlank(stored) ?? nonBlank(listed)
    }

    /// Stored id wins. Nil means there is no file to download.
    public static func downloadFileID(stored: String?, listed: String?) -> String? {
        nonBlank(stored) ?? nonBlank(listed)
    }

    public static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Android `SimpleDateFormat` patterns `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` and without millis.
    /// Parsed by hand so Linux and Darwin agree. Anything else is 0, the same as a failed parse.
    public static func parseRfc3339Millis(_ value: String?) -> Int64 {
        guard let value else { return 0 }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 20, text.hasSuffix("Z") else { return 0 }
        let body = text.dropLast()
        let parts = body.split(separator: "T", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return 0 }
        let dateParts = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard dateParts.count == 3,
              let year = Int(dateParts[0]),
              let month = Int(dateParts[1]),
              let day = Int(dateParts[2])
        else { return 0 }
        let clock = parts[1]
        let timeText: Substring
        var millis = 0
        if let dot = clock.firstIndex(of: ".") {
            timeText = clock[..<dot]
            let fraction = clock[clock.index(after: dot)...]
            guard fraction.count == 3, let parsed = Int(fraction) else { return 0 }
            millis = parsed
        } else {
            timeText = clock[...]
        }
        let timeParts = timeText.split(separator: ":", omittingEmptySubsequences: false)
        guard timeParts.count == 3,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]),
              let second = Int(timeParts[2]),
              (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...60).contains(second)
        else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = DateComponents(
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        guard let date = calendar.date(from: components) else { return 0 }
        return Int64(date.timeIntervalSince1970 * 1000) + Int64(millis)
    }

    public static func firstFile(in json: String) throws -> DriveRemoteFile? {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        } catch {
            throw DriveFailure.invalidJSON
        }
        guard let root = object as? [String: Any] else { throw DriveFailure.invalidJSON }
        guard let files = root["files"] as? [Any] else { return nil }
        guard let first = files.first as? [String: Any] else { return nil }
        guard let id = first["id"] as? String, !id.isEmpty else { throw DriveFailure.invalidJSON }
        let modified = first["modifiedTime"] as? String
        return DriveRemoteFile(id: id, modifiedAt: parseRfc3339Millis(modified))
    }
}

/// Android `GoogleDriveApiClient.withRetry`.
public enum DriveRetry {
    public static func perform<T>(
        maxAttempts: Int = DriveSyncPolicy.defaultMaxAttempts,
        sleep: (Int64) -> Void = { _ in },
        _ body: () throws -> T
    ) -> Result<T, DriveFailure> {
        var last: DriveFailure?
        for attempt in 0..<maxAttempts {
            do {
                return .success(try body())
            } catch let error as DriveFailure {
                if case .notSignedIn = error { return .failure(error) }
                if case .needsConsent = error { return .failure(error) }
                if case .invalidJSON = error { return .failure(error) }
                if giveUp(error, attempt: attempt, maxAttempts: maxAttempts) { return .failure(error) }
                last = error
            } catch {
                let wrapped = DriveFailure.io(error.localizedDescription)
                if giveUp(wrapped, attempt: attempt, maxAttempts: maxAttempts) { return .failure(wrapped) }
                last = wrapped
            }
            if attempt < maxAttempts - 1 {
                sleep(DriveSyncPolicy.backoffDelayMs(attemptIndex: attempt))
            }
        }
        return .failure(last ?? .api("Unknown Drive error"))
    }

    static func giveUp(_ error: DriveFailure, attempt: Int, maxAttempts: Int) -> Bool {
        !DriveSyncPolicy.isRetryableFailure(error.message) || attempt == maxAttempts - 1
    }
}

/// Drive v3 appDataFolder reads and writes. Scope is expressed by the bearer token, not by a query.
public final class DriveAPI {
    public var accessToken: String
    public var fileName: String
    public var storedFileID: String?
    public var transport: DriveTransport
    public var boundary: String
    public var sleep: (Int64) -> Void

    public init(
        accessToken: String,
        fileName: String,
        storedFileID: String? = nil,
        transport: DriveTransport,
        boundary: String = "truckerload_boundary",
        sleep: @escaping (Int64) -> Void = { _ in }
    ) {
        self.accessToken = accessToken
        self.fileName = fileName
        self.storedFileID = storedFileID
        self.transport = transport
        self.boundary = boundary
        self.sleep = sleep
    }

    public func upload(json: String) -> Result<DriveRemoteFile, DriveFailure> {
        DriveRetry.perform(sleep: sleep) {
            let token = try requireToken()
            let listed = try list(token: token)
            let existing = DriveHTTP.uploadFileID(stored: storedFileID, listed: listed?.id)
            let fileID: String
            if let existing {
                try update(token: token, fileID: existing, json: json)
                fileID = existing
            } else {
                fileID = try create(token: token, json: json)
            }
            storedFileID = fileID
            let refreshed = try list(token: token)
            let modified = refreshed?.modifiedAt ?? 0
            return DriveRemoteFile(id: fileID, modifiedAt: modified > 0 ? modified : 0)
        }
    }

    public func download() -> Result<(json: String, file: DriveRemoteFile), DriveFailure> {
        DriveRetry.perform(sleep: sleep) {
            let token = try requireToken()
            let listed = try list(token: token)
            guard let fileID = DriveHTTP.downloadFileID(stored: storedFileID, listed: listed?.id) else {
                throw DriveFailure.api("No backup on Google Drive yet")
            }
            storedFileID = fileID
            let json = try fetchMedia(token: token, fileID: fileID)
            let modified = listed?.modifiedAt ?? 0
            return (json, DriveRemoteFile(id: fileID, modifiedAt: modified))
        }
    }

    /// Failure is not "no file". Callers must not overwrite Drive when this throws.
    public func refreshRemote() -> Result<DriveRemoteFile?, DriveFailure> {
        DriveRetry.perform(sleep: sleep) {
            let token = try requireToken()
            let listed = try list(token: token)
            if let listed { storedFileID = listed.id }
            return listed
        }
    }

    private func requireToken() throws -> String {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { throw DriveFailure.notSignedIn }
        return token
    }

    private func list(token: String) throws -> DriveRemoteFile? {
        let response = try send(
            DriveHTTPRequest(
                method: "GET",
                url: DriveHTTP.listURL(fileName: fileName),
                headers: DriveHTTP.authorized(token)
            ),
            failure: "List failed"
        )
        return try DriveHTTP.firstFile(in: response.body)
    }

    private func create(token: String, json: String) throws -> String {
        let metadata = DriveHTTP.createMetadata(fileName: fileName)
        let body = DriveHTTP.multipartRelated(boundary: boundary, metadataJSON: metadata, fileJSON: json)
        var headers = DriveHTTP.authorized(token)
        headers["Content-Type"] = "multipart/related; boundary=\(boundary)"
        let response = try send(
            DriveHTTPRequest(
                method: "POST",
                url: "\(DriveHTTP.uploadRoot)?uploadType=multipart",
                headers: headers,
                body: body
            ),
            failure: "Upload failed"
        )
        guard let object = try? JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any],
              let id = object["id"] as? String,
              !id.isEmpty
        else { throw DriveFailure.invalidJSON }
        return id
    }

    private func update(token: String, fileID: String, json: String) throws {
        var headers = DriveHTTP.authorized(token)
        headers["Content-Type"] = "application/json; charset=UTF-8"
        _ = try send(
            DriveHTTPRequest(
                method: "PATCH",
                url: "\(DriveHTTP.uploadRoot)/\(pathEscape(fileID))?uploadType=media",
                headers: headers,
                body: json
            ),
            failure: "Update failed"
        )
    }

    private func fetchMedia(token: String, fileID: String) throws -> String {
        let response = try send(
            DriveHTTPRequest(
                method: "GET",
                url: "\(DriveHTTP.filesRoot)/\(pathEscape(fileID))?alt=media",
                headers: DriveHTTP.authorized(token)
            ),
            failure: "Download failed",
            includeBodyInError: false
        )
        let text = DriveJSON.stripBOM(response.body)
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            throw DriveFailure.invalidJSON
        }
        return text
    }

    private func send(
        _ request: DriveHTTPRequest,
        failure: String,
        includeBodyInError: Bool = true
    ) throws -> DriveHTTPResponse {
        let response: DriveHTTPResponse
        do {
            response = try transport.send(request)
        } catch let error as DriveFailure {
            throw error
        } catch {
            throw DriveFailure.io(error.localizedDescription)
        }
        guard (200..<300).contains(response.status) else {
            if includeBodyInError {
                throw DriveFailure.api("\(failure) (\(response.status)): \(response.body)")
            }
            throw DriveFailure.api("\(failure) (\(response.status))")
        }
        return response
    }

    private func pathEscape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum DriveJSON {
    static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    static func escape(_ raw: String) -> String {
        var out = "\""
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{0008}": out += "\\b"
            case "\u{000C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    /// Java `Double.toString` for the finite values a backup actually stores.
    static func renderDouble(_ value: Double) -> String {
        guard value.isFinite else { return "0.0" }
        let text = String(value)
        if text.contains(".") || text.contains("e") || text.contains("E") { return text }
        return text + ".0"
    }
}
