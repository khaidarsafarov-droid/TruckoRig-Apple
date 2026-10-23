import Foundation

public struct TelegramHTTPRequest: Equatable, Sendable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: String?
    public var timeout: TimeInterval

    public init(method: String, url: String, headers: [String: String] = [:], body: String? = nil, timeout: TimeInterval = 15) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct TelegramHTTPResponse: Equatable, Sendable {
    public var status: Int
    public var body: String

    public init(status: Int, body: String) {
        self.status = status
        self.body = body
    }
}

public struct TelegramHealth: Equatable, Sendable {
    public var ok: Bool
    public var username: String?
    public var unauthorized: Bool
    public var error: String?

    public static func parse(status: Int, body: String) -> TelegramHealth {
        if status == 401 {
            return TelegramHealth(
                ok: false,
                username: nil,
                unauthorized: true,
                error: "Invalid token (401). Get a new one from @BotFather → /token"
            )
        }
        if !(200...299).contains(status) {
            return TelegramHealth(ok: false, username: nil, unauthorized: false, error: TelegramRedactor.redact("HTTP \(status): \(body)"))
        }
        guard let json = TelegramJSON.object(body) else {
            return TelegramHealth(ok: false, username: nil, unauthorized: false, error: TelegramRedactor.redact(body))
        }
        let result = json["result"] as? [String: Any]
        let username = result?["username"] as? String
        return TelegramHealth(ok: (json["ok"] as? Bool) == true, username: username, unauthorized: false, error: nil)
    }
}

public struct TelegramUpdate: Equatable, Sendable {
    public var updateId: Int64
    public var chatId: String
    public var chatType: String
    public var text: String
    public var documentFileId: String?
    public var documentFileName: String?
    public var documentMimeType: String?
    public var documentFileSize: Int64?
    public var photoFileId: String?
    public var messageDateSeconds: Int64?
    public var callbackQueryId: String?
    public var isCallbackQuery: Bool

    public init(
        updateId: Int64,
        chatId: String,
        chatType: String,
        text: String,
        documentFileId: String? = nil,
        documentFileName: String? = nil,
        documentMimeType: String? = nil,
        documentFileSize: Int64? = nil,
        photoFileId: String? = nil,
        messageDateSeconds: Int64? = nil,
        callbackQueryId: String? = nil,
        isCallbackQuery: Bool = false
    ) {
        self.updateId = updateId
        self.chatId = chatId
        self.chatType = chatType
        self.text = text
        self.documentFileId = documentFileId
        self.documentFileName = documentFileName
        self.documentMimeType = documentMimeType
        self.documentFileSize = documentFileSize
        self.photoFileId = photoFileId
        self.messageDateSeconds = messageDateSeconds
        self.callbackQueryId = callbackQueryId
        self.isCallbackQuery = isCallbackQuery
    }
}

public struct TelegramUpdateBatch: Equatable, Sendable {
    public var updates: [TelegramUpdate]
    public var nextOffset: Int64
    public var rawMaxUpdateId: Int64
    public var unparsedUpdateIds: [Int64]
}

public enum TelegramBotAPI {
    public static let host = "https://api.telegram.org"
    public static let maxDownloadBytes: Int64 = 20 * 1024 * 1024
    public static let importMaxBytes: Int64 = 10 * 1024 * 1024
    public static let importMaxLoads = 100
    public static let jsonImportMaxLoads = 500
    public static let longPollSeconds = 25
    public static let readTimeout: TimeInterval = 70

    public static func root(_ token: String) -> String {
        host + "/bot" + TelegramTokenRules.normalized(token)
    }

    public static func getMe(_ token: String) -> TelegramHTTPRequest {
        TelegramHTTPRequest(method: "GET", url: root(token) + "/getMe", timeout: 12)
    }

    public static func deleteWebhook(_ token: String) -> TelegramHTTPRequest {
        TelegramHTTPRequest(method: "POST", url: root(token) + "/deleteWebhook?drop_pending_updates=false", timeout: 15)
    }

    public static func setMyName(_ token: String) -> TelegramHTTPRequest {
        json(token, "setMyName", TelegramBranding.setMyNameBody())
    }

    public static func setMyCommands(_ token: String) -> TelegramHTTPRequest {
        json(token, "setMyCommands", #"{"commands":\#(TelegramMenu.commandsJSON())}"#)
    }

    public static func setChatMenuButton(_ token: String) -> TelegramHTTPRequest {
        json(token, "setChatMenuButton", #"{"menu_button":{"type":"commands"}}"#)
    }

    public static func getUpdates(token: String, offset: Int64?, timeoutSeconds: Int = longPollSeconds, limit: Int = 100) -> TelegramHTTPRequest {
        let allowed = Self.formEncode(#"["message","callback_query"]"#)
        var url = root(token) + "/getUpdates?timeout=\(timeoutSeconds)&limit=\(min(100, max(1, limit)))&allowed_updates=\(allowed)"
        if let offset, offset > 0 { url += "&offset=\(offset)" }
        return TelegramHTTPRequest(method: "GET", url: url, timeout: readTimeout)
    }

    public static func sendMessage(token: String, chatId: String, text: String, replyMarkup: String? = nil, parseMode: String? = nil) -> TelegramHTTPRequest {
        var fields = [
            "chat_id": chatId,
            "text": text,
        ]
        if let parseMode { fields["parse_mode"] = parseMode }
        if let replyMarkup { fields["reply_markup"] = replyMarkup }
        return TelegramHTTPRequest(
            method: "POST",
            url: root(token) + "/sendMessage",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: form(fields),
            timeout: 15
        )
    }

    public static func answerCallback(token: String, callbackId: String, text: String) -> TelegramHTTPRequest {
        json(token, "answerCallbackQuery", #"{"callback_query_id":\#(TelegramJSON.string(callbackId)),"text":\#(TelegramJSON.string(text)),"show_alert":false}"#)
    }

    public static func sendChatAction(token: String, chatId: String) -> TelegramHTTPRequest {
        json(token, "sendChatAction", #"{"chat_id":\#(TelegramJSON.string(chatId)),"action":"typing"}"#)
    }

    public static func getFile(token: String, fileId: String) -> TelegramHTTPRequest {
        let encoded = Self.formEncode(fileId).replacingOccurrences(of: "+", with: "%20")
        return TelegramHTTPRequest(method: "GET", url: root(token) + "/getFile?file_id=\(encoded)", timeout: 20)
    }

    public static func fileURL(token: String, path: String) -> String {
        host + "/file/bot" + TelegramTokenRules.normalized(token) + "/" + path
    }

    public static func failureMessage(method: String, status: Int, body: String) -> String {
        TelegramRedactor.redact("\(method) failed: \(status) \(body)")
    }

    public static func requireOK(method: String, status: Int, body: String) -> String? {
        if !(200...299).contains(status) { return failureMessage(method: method, status: status, body: body) }
        guard let json = TelegramJSON.object(body) else { return nil }
        if json["ok"] is Bool, (json["ok"] as? Bool) == false {
            let description = json["description"] as? String ?? body
            return TelegramRedactor.redact("\(method) failed: \(description)")
        }
        return nil
    }

    public static func parseUpdates(_ body: String, requestedOffset: Int64?) -> TelegramUpdateBatch {
        guard let json = TelegramJSON.object(body), let rows = json["result"] as? [[String: Any]] else {
            return TelegramUpdateBatch(updates: [], nextOffset: requestedOffset ?? 0, rawMaxUpdateId: 0, unparsedUpdateIds: [])
        }
        var rawMax: Int64 = 0
        var parsedMax: Int64 = 0
        var unparsed: [Int64] = []
        var updates: [TelegramUpdate] = []
        for row in rows {
            let updateId = TelegramJSON.int64(row["update_id"])
            if updateId > rawMax { rawMax = updateId }
            if let parsed = parseUpdate(row) {
                updates.append(parsed)
                if updateId > parsedMax { parsedMax = updateId }
            } else if updateId > 0 {
                unparsed.append(updateId)
            }
        }
        let next: Int64
        if parsedMax > 0 {
            next = parsedMax + 1
        } else if let highest = unparsed.max() {
            next = highest + 1
        } else if let requestedOffset, requestedOffset > 0 {
            next = requestedOffset
        } else {
            next = 0
        }
        return TelegramUpdateBatch(updates: updates, nextOffset: next, rawMaxUpdateId: rawMax, unparsedUpdateIds: unparsed)
    }

    public static func parseUpdate(_ row: [String: Any]) -> TelegramUpdate? {
        if let callback = row["callback_query"] as? [String: Any] {
            let message = callback["message"] as? [String: Any]
            let chat = message?["chat"] as? [String: Any]
            let callbackId = callback["id"] as? String
            return TelegramUpdate(
                updateId: TelegramJSON.int64(row["update_id"]),
                chatId: chatId(chat),
                chatType: "private",
                text: callback["data"] as? String ?? "",
                callbackQueryId: callbackId?.isEmpty == false ? callbackId : nil,
                isCallbackQuery: true
            )
        }
        // edited_message is ignored so a correction does not replace a saved load.
        guard let message = (row["message"] as? [String: Any]) ?? (row["channel_post"] as? [String: Any]) else {
            return nil
        }
        let chat = message["chat"] as? [String: Any]
        var text = message["text"] as? String ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = message["caption"] as? String ?? ""
        }
        var documentFileId: String?
        var documentFileName: String?
        var documentMimeType: String?
        var documentFileSize: Int64?
        if let document = message["document"] as? [String: Any] {
            documentFileId = nonEmpty(document["file_id"] as? String)
            documentFileName = nonEmpty(document["file_name"] as? String)
            documentMimeType = nonEmpty(document["mime_type"] as? String)
            let size = TelegramJSON.int64(document["file_size"])
            documentFileSize = size > 0 ? size : nil
        }
        var photoFileId: String?
        if let photos = message["photo"] as? [[String: Any]], let largest = photos.last {
            photoFileId = nonEmpty(largest["file_id"] as? String)
        }
        let rawDate = TelegramJSON.int64(message["date"])
        let forwardDate = TelegramJSON.int64(message["forward_date"])
        let originDate = TelegramJSON.int64((message["forward_origin"] as? [String: Any])?["date"])
        let messageDate: Int64?
        if forwardDate > 0 {
            messageDate = forwardDate
        } else if originDate > 0 {
            messageDate = originDate
        } else if rawDate > 0 {
            messageDate = rawDate
        } else {
            messageDate = nil
        }
        return TelegramUpdate(
            updateId: TelegramJSON.int64(row["update_id"]),
            chatId: chatId(chat),
            chatType: (chat?["type"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "private",
            text: text,
            documentFileId: documentFileId,
            documentFileName: documentFileName,
            documentMimeType: documentMimeType,
            documentFileSize: documentFileSize,
            photoFileId: photoFileId,
            messageDateSeconds: messageDate
        )
    }

    public static func filePath(from body: String) -> String? {
        guard let json = TelegramJSON.object(body), let result = json["result"] as? [String: Any] else { return nil }
        let path = result["file_path"] as? String ?? ""
        return path.isEmpty ? nil : path
    }

    public static func declaredFileSize(from body: String) -> Int64 {
        guard let json = TelegramJSON.object(body), let result = json["result"] as? [String: Any] else { return -1 }
        return TelegramJSON.int64(result["file_size"])
    }

    private static func json(_ token: String, _ method: String, _ body: String) -> TelegramHTTPRequest {
        TelegramHTTPRequest(
            method: "POST",
            url: root(token) + "/" + method,
            headers: ["Content-Type": "application/json"],
            body: body,
            timeout: 15
        )
    }

    private static func form(_ fields: [String: String]) -> String {
        fields.keys.sorted().map { key in
            formEncode(key) + "=" + formEncode(fields[key] ?? "")
        }.joined(separator: "&")
    }

    /// `application/x-www-form-urlencoded`, same rules Telegram's Android client uses (space as `+`).
    private static func formEncode(_ value: String) -> String {
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

    private static func chatId(_ chat: [String: Any]?) -> String {
        guard let chat, let value = chat["id"] else { return "" }
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

enum TelegramJSON {
    static func object(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    static func int64(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) ?? 0 }
        return 0
    }

    static func string(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        guard let data, let text = String(data: data, encoding: .utf8), text.count >= 2 else {
            return "\"\""
        }
        return String(text.dropFirst().dropLast())
    }
}
