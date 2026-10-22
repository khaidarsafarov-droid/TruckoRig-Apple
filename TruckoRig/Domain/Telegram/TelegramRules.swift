import Foundation

/// Command menu, leftover reply-keyboard labels, and `/restore` phrasing.
public enum TelegramMenu {
    public static let help = "📋 Help"
    public static let status = "📊 Status"
    public static let load = "📦 Load"
    public static let pay = "💰 Paycheck"
    public static let importButton = "📥 Import"
    public static let restore = "🔄 Restore"
    public static let legacyHelp = "📋 Помощь"
    public static let legacyStatus = "📊 Статус"
    public static let legacyLoad = "📦 Лоуд"
    public static let legacyPay = "💰 Зарплата"
    public static let legacyImport = "📥 Импорт"
    public static let legacyRestore = "🔄 Восстановить"

    public static func commandsJSON() -> String {
        let commands: [(String, String)] = [
            ("start", "Start"),
            ("help", "How to use the bot"),
            ("status", "Data count in the app"),
            ("import", "Bulk import loads"),
            ("cancel", "Cancel import or a pending question"),
        ]
        let rows = commands.map { #"{"command":"\#($0.0)","description":"\#($0.1)"}"# }
        return "[" + rows.joined(separator: ",") + "]"
    }

    public static let removeKeyboardJSON = #"{"remove_keyboard":true}"#

    public static func isMenuButton(_ text: String) -> Bool {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
        case help, status, load, pay, importButton, restore,
             legacyHelp, legacyStatus, legacyLoad, legacyPay, legacyImport, legacyRestore:
            return true
        default:
            return false
        }
    }

    public static func menuButtonToCommand(_ text: String) -> String? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
        case help, legacyHelp: return "/help"
        case status, legacyStatus: return "/stats"
        case load, legacyLoad: return "/help_load"
        case pay, legacyPay: return "/help_pay"
        case importButton, legacyImport: return "/import"
        case restore, legacyRestore: return "/restore"
        default: return nil
        }
    }

    public static func alias(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSlash(trimmed, "/load") { return "/help_load" }
        if isSlash(trimmed, "/paycheck") { return "/help_pay" }
        return trimmed
    }

    public static func isRestoreRequest(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSlash(trimmed, "/restore") || isSlash(trimmed, "/восстановить") { return true }
        let normalized = normalize(trimmed)
        if normalized.isEmpty { return false }
        return ["востонави", "восстанови", "восстановить", "восстановление", "restore"].contains { normalized.contains($0) }
    }

    public static func isSlash(_ text: String, _ command: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.compare(command, options: .caseInsensitive) == .orderedSame
            || trimmed.lowercased().hasPrefix(command.lowercased() + "@")
            || trimmed.lowercased().hasPrefix(command.lowercased() + " ")
    }

    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        let kept = lowered.unicodeScalars.map { scalar -> Unicode.Scalar in
            let letter = (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
            let digit = scalar.value >= 48 && scalar.value <= 57
            if letter || digit {
                return scalar
            }
            if scalar.value >= 0x0430 && scalar.value <= 0x044F { return scalar }
            return Unicode.Scalar(32)
        }
        return String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

public enum TelegramPairingCode {
    public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    public static let length = 8

    public static func make(bytes: [UInt8]) -> String {
        var code = ""
        for index in 0..<length {
            let byte = index < bytes.count ? bytes[index] : 0
            code.append(alphabet[Int(byte) % alphabet.count])
        }
        return code
    }

    /// True when the `/start` argument matches the current code. Comparison is case-insensitive.
    public static func matches(stored: String, candidate: String) -> Bool {
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return !normalized.isEmpty && stored == normalized
    }
}

public enum TelegramStart {
    public static func isStart(_ text: String) -> Bool {
        TelegramMenu.isSlash(text, "/start")
    }

    public static func payload(_ text: String) -> String? {
        guard isStart(text) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = trimmed.firstIndex(of: " ") else { return nil }
        let rest = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// A private `/start` pairs the chat. Group chats and button taps do not.
    public static func shouldPair(text: String, isCallback: Bool, chatType: String) -> Bool {
        if isCallback { return false }
        let isPrivate = chatType == "private" || chatType.isEmpty
        return isPrivate && isStart(text)
    }
}

public enum TelegramChatGate: Equatable, Sendable {
    case accepted
    case justPaired
    case foreign
    case unpaired
}

public enum TelegramSyncRules {
    public static let maxAttempts = 5
    public static let baseDelayMs: Int64 = 1_000
    public static let maxDelayMs: Int64 = 30_000
    public static let maxPoisonRetries = 3
    public static let manualRestoreTimeoutMs: Int64 = 5 * 60 * 1000
    public static let conflictDelaySeconds: Int64 = 45
    public static let errorDelaySeconds: Int64 = 30

    public static func backoffDelayMs(attemptIndex: Int, baseDelayMs: Int64 = baseDelayMs) -> Int64 {
        let shift = min(8, max(0, attemptIndex))
        let exp = baseDelayMs * (Int64(1) << Int64(shift))
        return min(exp, maxDelayMs)
    }

    public static func isRetryable(_ errorMessage: String?) -> Bool {
        let message = (errorMessage ?? "").lowercased()
        if message.contains("401") || message.contains("unauthorized") || message.contains("token") { return false }
        return message.contains("timeout") || message.contains("connection") || message.contains("unable to resolve")
            || message.contains("503") || message.contains("502") || message.contains("429")
            || message.contains("failed") || message.contains("reset")
    }

    public static func shouldResetOffset(conflictDetected: Bool, unauthorized: Bool) -> Bool {
        conflictDetected && !unauthorized
    }

    public static func shouldStop(errorMessage: String?) -> Bool {
        errorMessage?.contains("401") == true
    }

    /// Reconnect at once. A pause leaves the next message sitting in Telegram.
    public static func delayAfterPoll(processed: Int, updatesNonEmpty: Bool) -> Int64 {
        _ = processed
        _ = updatesNonEmpty
        return 0
    }

    public static func nextDelaySeconds(status: Int) -> Int64 {
        status == 409 ? conflictDelaySeconds : errorDelaySeconds
    }

    public static func shouldDeadLetter(previousFailures: Int) -> Bool {
        previousFailures + 1 >= maxPoisonRetries
    }

    public static func restoreIsActive(lastActivityMs: Int64, nowMs: Int64, flagged: Bool) -> Bool {
        guard flagged else { return false }
        if lastActivityMs == 0 { return true }
        return nowMs - lastActivityMs <= manualRestoreTimeoutMs
    }
}

public enum TelegramLoadEdit {
    public static func isUndo(_ text: String) -> Bool { headIs(text, "/undo") }
    public static func isRate(_ text: String) -> Bool { headIs(text, "/rate") }
    public static func isTeach(_ text: String) -> Bool { headIs(text, "/teach") }

    public static func rateAmount(_ text: String) -> Double? {
        guard isRate(text) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = trimmed.firstIndex(of: " ") else { return nil }
        let rest = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return nil }
        return parseMoney(rest).flatMap { $0 > 0 ? $0 : nil }
    }

    public static func parseMoney(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Double(cleaned)
    }

    private static func headIs(_ text: String, _ command: String) -> Bool {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? ""
        return head.compare(command, options: .caseInsensitive) == .orderedSame
            || head.lowercased().hasPrefix(command.lowercased() + "@")
    }
}

/// Words on the same line, before the load number or rate the driver pointed at.
public enum TelegramBrokerLabel {
    private static let generic: Set<String> = ["total", "rate", "amount", "date", "miles", "price", "stop", "pickup", "delivery"]

    public static func labelBefore(text: String, token: String) -> String? {
        let needle = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.count < 2 { return nil }
        let digits = needle.filter(\.isNumber)
        for line in text.components(separatedBy: "\n") {
            guard let at = index(on: line, needle: needle, digits: digits) else { continue }
            let before = String(line.prefix(at))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":-$ "))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let words = before.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }.suffix(4)
            let label = words.joined(separator: " ")
            if label.count < 2 || !label.contains(where: { $0.isLetter }) { continue }
            if generic.contains(label.lowercased()) { continue }
            return label
        }
        return nil
    }

    private static func index(on line: String, needle: String, digits: String) -> Int? {
        if let range = line.range(of: needle, options: .caseInsensitive) {
            return line.distance(from: line.startIndex, to: range.lowerBound)
        }
        if digits.count < 3 { return nil }
        let lineDigits = line.filter(\.isNumber)
        guard lineDigits.contains(digits) else { return nil }
        return line.firstIndex(where: \.isNumber).map { line.distance(from: line.startIndex, to: $0) }
    }
}

public enum TelegramFiles {
    public static func baseName(_ fileName: String?) -> String {
        (fileName ?? "")
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map { String($0).lowercased() } ?? ""
    }

    public static func isTelegramExportName(_ fileName: String?) -> Bool {
        let base = baseName(fileName)
        guard !base.isEmpty else { return false }
        return base.range(of: #"^messages\d*\.html?$"#, options: .regularExpression) != nil
    }

    public static func isResultJSONName(_ fileName: String?) -> Bool {
        baseName(fileName) == "result.json"
    }

    public static func isHTML(_ fileName: String?, mime: String?) -> Bool {
        let name = baseName(fileName)
        let type = (mime ?? "").lowercased()
        if type == "text/html" || type == "application/xhtml+xml" { return true }
        if type == "application/octet-stream" && (name.hasSuffix(".html") || name.hasSuffix(".htm")) { return true }
        return name.hasSuffix(".html") || name.hasSuffix(".htm") || isTelegramExportName(fileName)
    }

    public static func isJSON(_ fileName: String?, mime: String?) -> Bool {
        let name = baseName(fileName)
        let type = (mime ?? "").lowercased()
        if type == "application/json" || type == "text/json" { return true }
        if type == "application/octet-stream" && name.hasSuffix(".json") { return true }
        return name.hasSuffix(".json") || isResultJSONName(fileName)
    }

    public static func isExportText(name: String?, mime: String?) -> Bool {
        let file = (name ?? "").lowercased()
        let type = (mime ?? "").lowercased()
        return file.hasSuffix(".txt") || type == "text/plain" || file.contains("trucklog_export") || file.contains("truckerload_export")
    }

    public static func isChatExport(name: String?) -> Bool {
        isTelegramExportName(name) || isResultJSONName(name)
    }
}

public enum TelegramReceiptData {
    public static let load = "rc:load"
    public static let diesel = "rc:diesel"
    public static let def = "rc:def"
    public static let paycheck = "rc:pay"
    public static let confirm = "rc:ok"
    public static let cancel = "rc:cancel"
    public static let typeAmount = "rc:type"
    public static let amountPrefix = "rc:amt:"

    public static func isCallback(_ data: String) -> Bool { data.hasPrefix("rc:") }

    public static func amountCallback(_ amount: Double) -> String {
        amountPrefix + String(format: "%.2f", amount)
    }

    public static func parseAmount(_ data: String) -> Double? {
        guard data.hasPrefix(amountPrefix) else { return nil }
        return Double(data.dropFirst(amountPrefix.count)).flatMap { $0 > 0 ? $0 : nil }
    }

    public static func amountPicker(yes: String, typeOwn: String, cancel: String?) -> String {
        var rows: [String] = []
        var first: [String] = [button(yes), button(typeOwn)]
        if let cancel, !cancel.isEmpty { first.append(button(cancel)) }
        rows.append("[" + first.joined(separator: ",") + "]")
        return #"{"keyboard":[\#(rows.joined(separator: ","))],"resize_keyboard":true,"one_time_keyboard":true}"#
    }

    public static func typeKeyboard(load: String, diesel: String, def: String, paycheck: String, cancel: String) -> String {
        let row1 = [button(load), button(diesel)].joined(separator: ",")
        let row2 = [button(def), button(paycheck)].joined(separator: ",")
        let row3 = button(cancel)
        return #"{"keyboard":[[\#(row1)],[\#(row2)],[\#(row3)]],"resize_keyboard":true,"one_time_keyboard":true}"#
    }

    public static func matchLabel(
        _ text: String,
        yes: String,
        typeOwn: String,
        cancel: String,
        load: String,
        diesel: String,
        defLabel: String,
        paycheck: String
    ) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("/") { return nil }
        if !yes.isEmpty && trimmed.compare(yes, options: .caseInsensitive) == .orderedSame { return confirm }
        if !typeOwn.isEmpty && trimmed.compare(typeOwn, options: .caseInsensitive) == .orderedSame { return typeAmount }
        if !cancel.isEmpty && trimmed.compare(cancel, options: .caseInsensitive) == .orderedSame { return Self.cancel }
        if !load.isEmpty && trimmed.compare(load, options: .caseInsensitive) == .orderedSame { return Self.load }
        if !diesel.isEmpty && trimmed.compare(diesel, options: .caseInsensitive) == .orderedSame { return Self.diesel }
        if !defLabel.isEmpty && trimmed.compare(defLabel, options: .caseInsensitive) == .orderedSame { return Self.def }
        if !paycheck.isEmpty && trimmed.compare(paycheck, options: .caseInsensitive) == .orderedSame { return Self.paycheck }
        if trimmed.count > 32 { return nil }
        guard let amount = TelegramLoadEdit.parseMoney(trimmed), amount > 0 else { return nil }
        return amountCallback(amount)
    }

    private static func button(_ text: String) -> String {
        #"{"text":\#(TelegramJSON.string(text))}"#
    }
}

/// Diesel / paycheck content hash. A salt separates DEF from diesel when the text overlaps.
public enum TelegramFingerprint {
    public static func diesel(_ rawText: String, salt: String?) -> String {
        let payload = (salt?.isEmpty == false) ? rawText + "|" + (salt ?? "") : rawText
        return TelegramSHA256.hex(payload)
    }
}
