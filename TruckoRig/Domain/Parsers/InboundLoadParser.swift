import Foundation

/// Every inbound parser Android `MessageParseService` runs, ranked the same way.
public enum InboundLoadParser {
    public static func parseAll(_ text: String, fileName: String? = nil, reference: Date = Date()) -> [ParsedLoad] {
        let groups = [
            LoadParseGroup(source: .json, loads: JsonLoadText.parseAll(text, reference: reference)),
            LoadParseGroup(source: .relay, loads: LoadMessageParser.parseAll(text, reference: reference)),
            LoadParseGroup(source: .delimited, loads: DelimitedLoadText.parseAll(text, reference: reference)),
            LoadParseGroup(source: .template, loads: BrokerTemplateText.parseOne(text, fileName: fileName, reference: reference).map { [$0] } ?? []),
            LoadParseGroup(source: .rateConfirmation, loads: RateConfirmationText.parseOne(text, reference: reference).map { [$0] } ?? []),
            LoadParseGroup(source: .flexible, loads: FlexibleLoadText.parseOne(text, reference: reference).map { [$0] } ?? []),
        ]
        return LoadCandidateRanker.choose(groups)
    }
}

public enum LoadParseSource: Int, Sendable {
    case json = 30
    case relay = 28
    case template = 23
    case rateConfirmation = 22
    case delimited = 18
    case flexible = 8

    var bonus: Int { rawValue }
}

public struct LoadParseGroup: Sendable {
    public var source: LoadParseSource
    public var loads: [ParsedLoad]
    public init(source: LoadParseSource, loads: [ParsedLoad]) {
        self.source = source
        self.loads = loads
    }
}

public enum LoadCandidateRanker {
    public static func choose(_ groups: [LoadParseGroup]) -> [ParsedLoad] {
        let viable = groups.filter { !$0.loads.isEmpty }
        guard !viable.isEmpty else { return [] }
        let relay = viable.filter { $0.source == .relay && $0.loads.contains { $0.totalRate > 0 } }
        let pool = relay.isEmpty ? viable : relay
        return pool.max { lhs, rhs in
            let left = groupScore(lhs)
            let right = groupScore(rhs)
            if left == right { return lhs.source.bonus < rhs.source.bonus }
            return left < right
        }?.loads ?? []
    }

    public static func keepDespiteReceipt(kind: String, loads: [ParsedLoad]) -> Bool {
        guard kind == "paycheck" || kind == "diesel" else { return true }
        let best = loads.map(loadScore).max() ?? 0
        return best >= 110
    }

    public static func loadScore(_ load: ParsedLoad) -> Int {
        var score = 0
        if load.totalRate > 0 { score += 40 }
        if !load.pointA.isEmpty { score += 20 }
        if !load.pointB.isEmpty { score += 20 }
        if load.totalMiles > 0 { score += 10 }
        if !load.tripId.isEmpty { score += 8 }
        if load.totalMiles > 0, load.totalRate > 0 {
            let rpm = load.totalRate / load.totalMiles
            if (0.8...8).contains(rpm) { score += 30 }
            if rpm < 0.3 || rpm > 20 { score -= 25 }
        }
        return score
    }

    private static func groupScore(_ group: LoadParseGroup) -> Int {
        (group.loads.map(loadScore).max() ?? 0) + group.source.bonus
    }
}

enum FlexibleLoadText {
    static func parseOne(_ raw: String, reference: Date) -> ParsedLoad? {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard let rate = first(text, patterns: [
            #"Total\s*Rate\s*[:\s]*\$?\s*([\d.,]+)"#,
            #"Line\s*-?\s*Haul(?:\s*Rate)?\s*[:\s]*\$?\s*([\d.,]+)"#,
            #"All[\s-]?in(?:\s*rate)?\s*[:\s]*\$?\s*([\d.,]+)"#,
            #"(?:Rate|Pay|Оплата|Ставка)\s*[:\s]*\$?\s*([\d.,]+)"#,
        ]), rate > 0 else { return nil }
        let pickup = first(text, patterns: [#"Pu[\s\-]*address\s*:\s*(.+)"#, #"Pickup(?:\s*(?:Location|City))?\s*:\s*(.+)"#, #"\bFrom\b\s*:\s*(.+)"#, #"Origin\s*:\s*(.+)"#])
        let delivery = first(text, patterns: [#"Del[\s\-]*address\s*:\s*(.+)"#, #"Delivery(?:\s*(?:Location|City))?\s*:\s*(.+)"#, #"\bTo\b\s*:\s*(.+)"#, #"Destination\s*:\s*(.+)"#])
        guard pickup != nil || delivery != nil else { return nil }
        let milesRaw = first(text, patterns: [#"Total\s*Loaded\s*Miles\s*[:\s]*([\d.,]+)"#, #"(?:Loaded\s*Miles|Miles|Distance)\s*[:\s]*([\d.,]+)"#]) ?? 0
        let miles = NumberParsing.sanitizeLoadedMiles(milesRaw, totalRate: rate)
        let trip = firstText(text, patterns: [#"Trip\s*ID\s*[:\|]?\s*(T-[A-Z0-9]+)"#, #"(?:Load\s*(?:ID|#|Number)|Confirmation(?:\s*Number)?)\s*[:\|]?\s*([A-Z0-9\-]{4,})"#])?.uppercased()
            ?? "T-\(Int(reference.timeIntervalSince1970))"
        return make(tripId: trip, rate: rate, miles: miles, pickup: pickup, delivery: delivery, raw: raw, reference: reference)
    }
}

enum RateConfirmationText {
    static func parseOne(_ raw: String, reference: Date) -> ParsedLoad? {
        let marker = #"rate[\s\-]*confirmation|load[\s\-]*confirmation|estimated\s*rate|IEL\s*PO|rate\s*con\b"#
        guard raw.range(of: marker, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return FlexibleLoadText.parseOne(raw, reference: reference)
            ?? labeled(raw, reference: reference)
    }

    private static func labeled(_ raw: String, reference: Date) -> ParsedLoad? {
        guard let rate = first(raw, patterns: [#"Estimated\s*Rate(?:[^$\n]{0,48})\$\s*([\d,]+(?:\.\d{2})?)"#, #"Total\s*:\s*\$\s*([\d,]+(?:\.\d{2})?)"#]), rate > 0 else { return nil }
        let trip = firstText(raw, patterns: [#"IEL\s*PO\s*#\s*:?\s*([A-Z0-9\-]{4,})"#, #"(?:Load|Confirmation|Trip)\s*(?:ID|#|Number)\s*:?\s*([A-Z0-9\-]{4,})"#])?.uppercased()
            ?? "T-\(Int(reference.timeIntervalSince1970))"
        let pickup = firstText(raw, patterns: [#"Shipper\s*:?\s*(.+)"#, #"Pick\s*ups?\s*:?\s*(.+)"#])
        let delivery = firstText(raw, patterns: [#"Consignee\s*:?\s*(.+)"#, #"Deliver(?:y|ies)\s*:?\s*(.+)"#])
        guard pickup != nil || delivery != nil else { return nil }
        let miles = NumberParsing.sanitizeLoadedMiles(first(raw, patterns: [#"([\d.,]+)\s*miles?"#]) ?? 0, totalRate: rate)
        return make(tripId: trip, rate: rate, miles: miles, pickup: pickup, delivery: delivery, raw: raw, reference: reference)
    }
}

enum BrokerTemplateText {
    private static let keywords = ["integrity express", "iel po", "schneider", "jb hunt", "landstar", "echo global", "coyote"]

    static func parseOne(_ raw: String, fileName: String?, reference: Date) -> ParsedLoad? {
        let haystack = (raw + " " + (fileName ?? "")).lowercased()
        guard keywords.contains(where: { haystack.contains($0) }) else { return nil }
        return RateConfirmationText.parseOne(raw, reference: reference) ?? FlexibleLoadText.parseOne(raw, reference: reference)
    }
}

enum DelimitedLoadText {
    static func parseAll(_ raw: String, reference: Date) -> [ParsedLoad] {
        let lines = raw.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 2 else { return [] }
        let delimiter: Character = lines[0].contains("\t") ? "\t" : (lines[0].contains(";") ? ";" : ",")
        let header = split(lines[0], delimiter)
        guard header.count >= 2 else { return [] }
        return lines.dropFirst().compactMap { line in
            let cells = split(line, delimiter)
            var labeled: [String] = []
            for (index, name) in header.enumerated() where index < cells.count {
                labeled.append("\(name): \(cells[index])")
            }
            return FlexibleLoadText.parseOne(labeled.joined(separator: "\n"), reference: reference)
        }
    }

    private static func split(_ line: String, _ delimiter: Character) -> [String] {
        line.split(separator: delimiter, omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

enum JsonLoadText {
    static func parseAll(_ raw: String, reference: Date) -> [ParsedLoad] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let messages = (root as? [String: Any])?["messages"] as? [[String: Any]] {
            let text = messages.compactMap { $0["text"] as? String }.joined(separator: "\n\n")
            return LoadMessageParser.parseAll(text, reference: reference)
        }
        return nodes(root).compactMap { object in
            load(from: object, raw: raw, reference: reference)
        }
    }

    private static func nodes(_ root: Any) -> [[String: Any]] {
        if let array = root as? [[String: Any]] { return array }
        guard let object = root as? [String: Any] else { return [] }
        for key in ["loads", "shipments", "orders", "trips", "data", "results", "items", "records"] {
            if let array = object[key] as? [[String: Any]] { return array }
        }
        for key in ["load", "shipment", "order", "trip", "payload", "result"] {
            if let child = object[key] as? [String: Any] { return nodes(child) }
        }
        return [flatten(object)]
    }

    private static func flatten(_ object: [String: Any]) -> [String: Any] {
        var flat: [String: Any] = [:]
        for (key, value) in object {
            let normalized = key.lowercased().replacingOccurrences(of: "_", with: "")
            if let child = value as? [String: Any] {
                for (nestedKey, nested) in flatten(child) {
                    flat[nestedKey] = nested
                }
            } else {
                flat[normalized] = value
            }
        }
        return flat
    }

    private static func load(from flat: [String: Any], raw: String, reference: Date) -> ParsedLoad? {
        let rate = number(flat, ["totalrate", "linehaul", "rate", "revenue", "gross", "amount", "pay", "price", "total"])
        guard rate > 0 else { return nil }
        let pickup = text(flat, ["puaddress", "pickup", "origin", "from", "shipper"])
        let delivery = text(flat, ["deladdress", "delivery", "destination", "to", "consignee"])
        guard pickup != nil || delivery != nil else { return nil }
        let miles = NumberParsing.sanitizeLoadedMiles(
            number(flat, ["totalloadedmiles", "loadedmiles", "totalmiles", "miles", "distance"]),
            totalRate: rate
        )
        let trip = text(flat, ["tripid", "trip", "loadid", "loadnumber", "confirmation", "reference"])?.uppercased()
            ?? "T-\(Int(reference.timeIntervalSince1970))"
        return make(tripId: trip, rate: rate, miles: miles, pickup: pickup, delivery: delivery, raw: raw, reference: reference)
    }

    private static func number(_ flat: [String: Any], _ keys: [String]) -> Double {
        for key in keys {
            if let value = flat[key] {
                if let number = value as? NSNumber { return number.doubleValue }
                if let text = value as? String { return NumberParsing.parseMoney(text) }
            }
        }
        return 0
    }

    private static func text(_ flat: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = flat[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

func first(_ text: String, patterns: [String]) -> Double? {
    guard let raw = firstText(text, patterns: patterns) else { return nil }
    let value = NumberParsing.parseMoney(raw)
    return value > 0 ? value : NumberParsing.parseMiles(raw)
}

func firstText(_ text: String, patterns: [String]) -> String? {
    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let span = Range(match.range(at: 1), in: text) else { continue }
        let value = String(text[span]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { return value }
    }
    return nil
}

func make(tripId: String, rate: Double, miles: Double, pickup: String?, delivery: String?, raw: String, reference: Date) -> ParsedLoad {
    var stops: [StopDraft] = []
    if let pickup { stops.append(addressStop(.pickup, pickup, number: 1)) }
    if let delivery { stops.append(addressStop(.delivery, delivery, number: stops.count + 1)) }
    return ParsedLoad(tripId: tripId, totalRate: rate, totalMiles: miles, date: reference, stops: stops, rawMessage: raw)
}

func addressStop(_ type: StopType, _ address: String, number: Int) -> StopDraft {
    let parts = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let city = parts.first ?? address
    let state = parts.dropFirst().first.map { String($0.prefix(2)).uppercased() } ?? ""
    return StopDraft(type: type, stopNumber: number, fullAddress: address, city: city, state: state)
}
