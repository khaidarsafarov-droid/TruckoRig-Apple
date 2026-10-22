import Foundation

public enum TelegramInbound: Equatable, Sendable {
    /// A complete load. The engine saves it and replies with the trip, rate, miles, and cities.
    case saveLoads([ParsedLoad])
    /// The text looks like a load, but Trip ID, rate, or an address is missing.
    case missingFields([String])
    /// Paycheck, diesel, or DEF. The bot asks before writing the journal.
    case confirm(kind: String, amount: Double?, gallons: Double?, pricePerGallon: Double?, location: String?, driverName: String?, weekHint: String?)
    /// Settlement shape without a take-home total.
    case paycheckAmountMissing
    case unrecognized
}

/// Same gate as Android `InboundDocumentResolver`: a clear load is saved, a receipt is confirmed.
public enum TelegramIngest {
    public static func decide(_ text: String, fileName: String? = nil, reference: Date = Date()) -> TelegramInbound {
        let loads = LoadMessageParser.parseAll(text, reference: reference)
        let scores = ReceiptKindClassifier.scoreMap(text, fileName: fileName)
        let loadScore = scores[.load] ?? 0
        let paycheckScore = scores[.paycheck] ?? 0
        let fuelScore = max(scores[.diesel] ?? 0, scores[.def] ?? 0)
        let looksLikeLoad = loadScore >= 6 && loadScore > paycheckScore && loadScore >= fuelScore
        let kind = ReceiptKindClassifier.classify(text, fileName: fileName)
        let autoSave = !loads.isEmpty && paycheckScore < loadScore && (
            kind == .load || kind == .unknown || (loadScore >= 6 && loadScore >= fuelScore)
        )
        if autoSave { return .saveLoads(loads) }
        if loads.isEmpty && looksLikeLoad {
            return .missingFields(missing(in: text, languageFields: true))
        }
        if kind == .paycheck || PaycheckTextParser.looksLikePaycheck(text, fileName: fileName) {
            if let parsed = PaycheckTextParser.parse(text, fileName: fileName), parsed.netAmount > 0 {
                return .confirm(
                    kind: "paycheck",
                    amount: parsed.netAmount,
                    gallons: nil,
                    pricePerGallon: nil,
                    location: nil,
                    driverName: parsed.driverName,
                    weekHint: parsed.weekStartDate
                )
            }
            return .paycheckAmountMissing
        }
        if kind == .def {
            let parsed = DieselTextParser.parse(text)
            return .confirm(
                kind: "def",
                amount: parsed?.totalAmount,
                gallons: parsed?.gallons,
                pricePerGallon: parsed?.pricePerGallon,
                location: parsed?.location,
                driverName: nil,
                weekHint: parsed?.date
            )
        }
        if kind == .diesel || DieselTextParser.looksLikeDiesel(text) {
            if let parsed = DieselTextParser.parse(text), parsed.totalAmount > 0 {
                return .confirm(
                    kind: "diesel",
                    amount: parsed.totalAmount,
                    gallons: parsed.gallons,
                    pricePerGallon: parsed.pricePerGallon,
                    location: parsed.location,
                    driverName: nil,
                    weekHint: parsed.date
                )
            }
        }
        if !loads.isEmpty { return .saveLoads(loads) }
        return .unrecognized
    }

    public static func missing(in text: String, languageFields: Bool) -> [String] {
        _ = languageFields
        var fields: [String] = []
        if !MessageClassifier.isLoadLike(text) || text.range(of: #"T-[A-Z0-9]{6,}|Trip\s*ID"#, options: [.regularExpression, .caseInsensitive]) == nil {
            fields.append("trip")
        }
        if text.range(of: #"Total\s*Rate|Rate\s+\$"#, options: [.regularExpression, .caseInsensitive]) == nil {
            fields.append("rate")
        }
        if text.range(of: #"\b(PU|DEL|pickup|delivery)\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
            fields.append("pickup")
        }
        return fields
    }

    public static func fieldLabel(_ key: String, _ language: TelegramLanguage) -> String {
        switch (key, language) {
        case ("trip", .ru): return "Trip ID"
        case ("trip", .en): return "Trip ID"
        case ("rate", .ru): return "ставка"
        case ("rate", .en): return "rate"
        case ("pickup", .ru): return "адрес погрузки"
        case ("pickup", .en): return "pickup address"
        case ("delivery", .ru): return "адрес выгрузки"
        case ("delivery", .en): return "delivery address"
        case ("miles", .ru): return "мили"
        case ("miles", .en): return "miles"
        case ("date", .ru): return "дата"
        case ("date", .en): return "date"
        default: return key
        }
    }

    public static func savedLoadReply(_ load: ParsedLoad, added: Bool, language: TelegramLanguage) -> String {
        let headKey = added ? "load_added" : "load_skipped"
        let head = TelegramCopy.text(headKey, language, load.tripId)
        let detail = TelegramLoadReply.detail(
            rate: load.totalRate,
            miles: load.totalMiles,
            origin: load.pointA,
            destination: load.pointB
        )
        return detail.isEmpty ? head : head + "\n" + detail
    }

    public static func duplicateReply(_ tripId: String, _ language: TelegramLanguage) -> String {
        TelegramCopy.text("load_skipped", language, tripId)
    }
}

public struct TelegramExportMessage: Equatable, Sendable {
    public var text: String
    public var reference: Date?

    public init(text: String, reference: Date?) {
        self.text = text
        self.reference = reference
    }
}

/// Telegram Desktop `messages.html` and `result.json`. Each message is parsed on its own date.
public enum TelegramExportText {
    public static func isHTMLExport(_ html: String) -> Bool {
        html.contains("page_wrap") && html.contains("history") && html.contains("message default") && html.contains("from_name")
    }

    public static func isJSONExport(_ json: String) -> Bool {
        guard let root = TelegramJSON.object(json.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return root["messages"] is [Any] && (root["name"] != nil || root["type"] != nil || root["id"] != nil)
    }

    public static func htmlMessages(_ html: String) -> [TelegramExportMessage] {
        let chunks = html.components(separatedBy: "class=\"message")
        var messages: [TelegramExportMessage] = []
        for chunk in chunks.dropFirst() {
            if chunk.hasPrefix(" service") || chunk.contains("class=\"body details\"") && !chunk.contains("class=\"text") {
                continue
            }
            let sender = firstCapture(chunk, #"class="from_name"[^>]*>([^<]+)"#) ?? ""
            guard let raw = textDiv(chunk) else { continue }
            let text = strip(raw)
            if text.isEmpty || isSystem(sender: sender, text: text) { continue }
            messages.append(TelegramExportMessage(text: text, reference: titleDate(chunk)))
        }
        return messages
    }

    public static func jsonMessages(_ json: String) -> [TelegramExportMessage] {
        guard let root = TelegramJSON.object(json), let rows = root["messages"] as? [[String: Any]] else { return [] }
        var messages: [TelegramExportMessage] = []
        for row in rows {
            if (row["type"] as? String) != "message" { continue }
            let text = flatten(row["text"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            var reference: Date?
            if let unix = row["date_unixtime"] {
                let seconds = TelegramJSON.int64(unix)
                if seconds > 0 { reference = Date(timeIntervalSince1970: TimeInterval(seconds)) }
            }
            if reference == nil, let date = row["date"] as? String {
                reference = titleDate(date)
            }
            messages.append(TelegramExportMessage(text: StyledTextNormalizer.normalize(text), reference: reference))
        }
        return messages
    }

    /// Latest copy of each Trip ID wins, matching Android `ImportTripDedup.keepLatestByTripId`.
    public static func loads(in messages: [TelegramExportMessage], fallback: Date = Date()) -> [ParsedLoad] {
        var order: [String] = []
        var byTrip: [String: ParsedLoad] = [:]
        for message in messages {
            let parsed = LoadMessageParser.parseAll(message.text, reference: message.reference ?? fallback)
            for load in parsed {
                let key = TripID.normalize(load.tripId)
                if byTrip[key] == nil { order.append(key) }
                byTrip[key] = load
            }
        }
        return order.compactMap { byTrip[$0] }
    }

    private static func textDiv(_ chunk: String) -> String? {
        guard let range = chunk.range(of: "class=\"text") else { return nil }
        let tail = chunk[range.lowerBound...]
        guard let open = tail.range(of: ">") else { return nil }
        let body = tail[open.upperBound...]
        if let end = body.range(of: "</div>") {
            return String(body[..<end.lowerBound])
        }
        return String(body.prefix(12_000))
    }

    private static func strip(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        return StyledTextNormalizer.normalize(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func titleDate(_ chunk: String) -> Date? {
        guard let title = firstCapture(chunk, #"title="(\d{1,2}\.\d{1,2}\.\d{4}[^"]*)""#) else { return nil }
        return parseEuropean(title)
    }

    private static func parseEuropean(_ title: String) -> Date? {
        guard let match = title.range(of: #"(\d{1,2})\.(\d{1,2})\.(\d{4})(?:[ T](\d{1,2}):(\d{2}))?"#, options: .regularExpression) else {
            return nil
        }
        let piece = String(title[match])
        let parts = piece.split { !("0"..."9").contains($0) }.map { Int($0) ?? 0 }
        guard parts.count >= 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var components = DateComponents()
        components.day = parts[0]
        components.month = parts[1]
        components.year = parts[2]
        components.hour = parts.count > 3 ? parts[3] : 0
        components.minute = parts.count > 4 ? parts[4] : 0
        return calendar.date(from: components)
    }

    private static func flatten(_ value: Any?) -> String {
        if let text = value as? String { return text }
        guard let rows = value as? [Any] else { return "" }
        return rows.map { item -> String in
            if let text = item as? String { return text }
            if let object = item as? [String: Any] { return object["text"] as? String ?? "" }
            return ""
        }.joined()
    }

    private static func isSystem(sender: String, text: String) -> Bool {
        let blocked = ["Telegram", "System", "Channel", "Group"]
        if blocked.contains(where: { sender.range(of: $0, options: .caseInsensitive) != nil }) { return true }
        let lowered = text.lowercased()
        return lowered.contains("joined the group") || lowered.contains("pinned a message") || lowered.contains("changed the group photo")
    }

    private static func firstCapture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let hit = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[hit])
    }
}

public enum TelegramDedupReport {
    public static func text(
        loadsScanned: Int,
        loadsRemoved: Int,
        paychecksRemoved: Int,
        dieselRemoved: Int,
        removedTrips: [String],
        elapsedMs: Int,
        language: TelegramLanguage
    ) -> String {
        if loadsRemoved + paychecksRemoved + dieselRemoved == 0 {
            return TelegramCopy.text("sync_dedup_none", language)
        }
        var lines = [
            TelegramCopy.text("sync_dedup_done_title", language),
            TelegramCopy.text("sync_dedup_scanned", language, String(loadsScanned)),
            TelegramCopy.text("sync_dedup_deleted_loads", language, String(loadsRemoved)),
            TelegramCopy.text("sync_dedup_deleted_paychecks", language, String(paychecksRemoved)),
            TelegramCopy.text("sync_dedup_deleted_diesel", language, String(dieselRemoved)),
            TelegramCopy.text("sync_dedup_duration", language, String(elapsedMs)),
        ]
        if !removedTrips.isEmpty {
            lines.append(TelegramCopy.text("sync_dedup_removed_loads", language))
            lines.append(contentsOf: removedTrips)
        }
        return lines.joined(separator: "\n")
    }
}
