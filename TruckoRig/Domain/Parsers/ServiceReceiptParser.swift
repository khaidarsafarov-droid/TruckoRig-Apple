import Foundation

/// One priced row on a service receipt. Port of `ServiceReceiptLineItems.LineItem`.
public struct ServiceReceiptLine: Equatable, Sendable {
    public var description: String
    public var amount: Double

    public init(description: String, amount: Double) {
        self.description = description
        self.amount = amount
    }
}

/// Parsed service / truck-stop receipt. Port of `ServiceReceiptTextParser.ParseResult`.
public struct ServiceReceiptParse: Equatable, Sendable {
    public var amount: Double?
    public var date: String?
    public var serviceName: String?
    public var descriptionHint: String?
    public var lineItems: [ServiceReceiptLine]

    public init(
        amount: Double?,
        date: String?,
        serviceName: String?,
        descriptionHint: String?,
        lineItems: [ServiceReceiptLine]
    ) {
        self.amount = amount
        self.date = date
        self.serviceName = serviceName
        self.descriptionHint = descriptionHint
        self.lineItems = lineItems
    }
}

/// Smart heuristics for service receipt OCR text.
///
/// Port of `ServiceReceiptTextParser` plus `ServiceReceiptLineItems`. Prefers a labeled total
/// over line prices. Vendor comes from the header. Each service row keeps its own amount.
public enum ServiceReceiptParser {

    public static func parse(_ text: String, defaultDate: String) -> ServiceReceiptParse {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ServiceReceiptParse(amount: nil, date: defaultDate, serviceName: nil, descriptionHint: nil, lineItems: [])
        }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let amount = extractTotal(text, lines: lines)
        let date = extractDate(text) ?? defaultDate
        let serviceName = extractServiceName(text, lines: lines)
        let hint = extractDescription(lines, serviceName: serviceName)
        let items = ServiceReceiptLines.extract(lines).filter { item in
            guard let serviceName, !serviceName.isEmpty else { return true }
            return item.description.caseInsensitiveCompare(serviceName) != .orderedSame
        }
        return ServiceReceiptParse(
            amount: amount,
            date: date,
            serviceName: serviceName,
            descriptionHint: hint,
            lineItems: items
        )
    }

    private static let knownServices = [
        "Love's", "Loves", "TA Truck Service", "TA Petro", "TravelCenters of America", "TravelCenters",
        "Travel Centers", "Petro Stopping Centers", "Petro Stopping", "Pilot Flying J", "Flying J",
        "Pilot", "Speedco", "Jiffy Lube", "Firestone", "Goodyear", "Pep Boys", "NAPA", "FleetPride",
        "Fleet Pride", "TruckPro", "Kenworth", "Peterbilt", "Freightliner", "Volvo Trucks",
        "Interstate Batteries", "Truck Service",
    ]

    private static let labeledTotals: [(Int, Rx)] = [
        (100, Rx(#"(?:Grand\s*Total|Amount\s*Due|Balance\s*Due|Total\s*Due|Total\s*Amount|Amount\s*Paid|Итого\s*к\s*оплате|Всего\s*к\s*оплате)\s*[:\s]*\$?\s*([\d\s,]+\.?\d*)"#)),
        (80, Rx(#"(?:^|\n)\s*(?:TOTAL|ИТОГО|ВСЕГО|СУММА)\s*[:\s]*\$?\s*([\d\s,]+\.?\d*)"#)),
        (60, Rx(#"(?:Total|Итого|Всего|Сумма)\s*[:\s]*\$?\s*([\d\s,]+\.?\d*)"#)),
    ]

    private static let bareDollar = Rx(#"\$\s*([\d,]+\.\d{2})\b"#)
    private static let moneyTail = Rx(#"([\d,]+\.\d{2})\b"#)
    private static let intermediate = Rx(#"\b(?:sub\s*-?\s*total|subtotal|tax|sales\s*tax|tip|gratuity|discount|deposit|change(?!\s+oil)|cash\s*tendered|qty|quantity|unit\s*price|each)\b"#)
    private static let grandOverride = Rx(#"grand\s*total|amount\s*due|balance\s*due"#)
    private static let dateLabeled = Rx(#"(?:Date|Дата|Invoice\s*Date|Service\s*Date|Trans(?:action)?\s*Date)\s*[:\s]*([^\n]+)"#)
    private static let dateISO = Rx(#"\b(\d{4}-\d{2}-\d{2})\b"#)
    private static let dateNumeric = Rx(#"\b(\d{1,2}[./-]\d{1,2}[./-]\d{2,4})\b"#)
    private static let dateTextMonth = Rx(#"\b((?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:t(?:ember)?)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\.?\s+\d{1,2}(?:,)?\s+\d{2,4})\b"#)
    private static let skipVendor = Rx(#"total|итого|amount|date|дата|invoice|phone|tel|fax|www\.|http|receipt|thank|subtotal|tax|qty|item|visa|mastercard|cash|balance|miles?|mi\b|gal|gallon|street|road|ave|blvd|suite|ste\b"#)
    private static let skipDescription = Rx(#"total|итого|amount|date|дата|invoice|phone|tel|fax|www\.|http|receipt|thank|subtotal|tax|qty|item|visa|mastercard|cash|change\s+due|balance\s+due|miles?|mi\b|gal|gallon"#)
    private static let phone = Rx(#"^\(?\d{3}\)?[.\-\s]?\d{3}[.\-\s]?\d{4}"#)
    private static let startsDigit = Rx(#"^\d"#)

    private static func extractTotal(_ text: String, lines: [String]) -> Double? {
        var bestScore = -1
        var bestAmount: Double?
        for (score, pattern) in labeledTotals {
            for match in pattern.matches(in: text) {
                let rawLine = lineContaining(text, match: match)
                if let rawLine, intermediate.containsMatch(in: rawLine), !grandOverride.containsMatch(in: rawLine) {
                    continue
                }
                guard let raw = match.group(1), let value = DecimalInput.parse(raw), value > 0 else { continue }
                if score > bestScore || (score == bestScore && value > (bestAmount ?? 0)) {
                    bestScore = score
                    bestAmount = value
                }
            }
        }
        if let bestAmount { return bestAmount }

        let candidates = bareDollar.matches(in: text).compactMap { match -> Double? in
            let rawLine = lineContaining(text, match: match)
            if let rawLine, intermediate.containsMatch(in: rawLine) { return nil }
            guard let raw = match.group(1) else { return nil }
            return DecimalInput.parse(raw).flatMap { $0 > 0 ? $0 : nil }
        }
        if candidates.isEmpty {
            for line in lines.reversed() {
                if intermediate.containsMatch(in: line) { continue }
                if let raw = bareDollar.firstMatch(in: line)?.group(1), let value = DecimalInput.parse(raw), value > 0 {
                    return value
                }
                if let raw = moneyTail.firstMatch(in: line)?.group(1), let value = DecimalInput.parse(raw), value > 0 {
                    return value
                }
            }
            return nil
        }
        return candidates.last
    }

    private static func extractDate(_ text: String) -> String? {
        if let raw = dateLabeled.firstMatch(in: text)?.group(1) {
            if let iso = ReceiptDates.normalize(raw), !iso.isEmpty { return iso }
            if let iso = ReceiptDates.normalizeTextMonth(raw), !iso.isEmpty { return iso }
        }
        if let raw = dateISO.firstMatch(in: text)?.group(1), let iso = ReceiptDates.normalize(raw), !iso.isEmpty {
            return iso
        }
        if let raw = dateTextMonth.firstMatch(in: text)?.group(1), let iso = ReceiptDates.normalizeTextMonth(raw), !iso.isEmpty {
            return iso
        }
        if let raw = dateNumeric.firstMatch(in: text)?.group(1), let iso = ReceiptDates.normalize(raw), !iso.isEmpty {
            return iso
        }
        return nil
    }

    private static func extractServiceName(_ text: String, lines: [String]) -> String? {
        let header = Array(lines.prefix(5))
        if let known = knownServices.first(where: { text.range(of: $0, options: .caseInsensitive) != nil }) {
            let match = header.first { line in
                line.range(of: known, options: .caseInsensitive) != nil
                    && (known.count...80).contains(line.count)
                    && !line.contains("$")
            } ?? lines.first { line in
                line.range(of: known, options: .caseInsensitive) != nil
                    && (known.count...80).contains(line.count)
                    && !line.contains("$")
            }
            if let match { return String(match.prefix(80)) }
            return known
        }
        return header.first { line in
            (3...60).contains(line.count)
                && !line.contains("$")
                && !startsDigit.containsMatch(in: line)
                && !skipVendor.containsMatch(in: line)
                && !phone.containsMatch(in: line)
                && line.filter(\.isLetter).count >= 3
        }
    }

    private static func extractDescription(_ lines: [String], serviceName: String?) -> String? {
        lines.first { line in
            (3...80).contains(line.count)
                && !line.contains("$")
                && !startsDigit.containsMatch(in: line)
                && !skipDescription.containsMatch(in: line)
                && line.caseInsensitiveCompare(serviceName ?? "") != .orderedSame
                && !(serviceName != nil
                    && line.range(of: serviceName ?? "", options: .caseInsensitive) != nil
                    && line.count <= (serviceName?.count ?? 0) + 4)
        }
    }

    private static func lineContaining(_ text: String, match: RxMatch) -> String? {
        let start = text[..<match.range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let end = text[match.range.lowerBound...].firstIndex(of: "\n") ?? text.endIndex
        return text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ServiceReceiptLines {
    private static let skip = Rx(#"\b(?:grand\s*total|\btotals?\b|amount\s*(?:due|paid)|balance\s*due|total\s*(?:due|amount)|sub\s*-?\s*total|subtotal|sales\s*tax|\btax\b|tip|gratuity|discount|change\s*due|итого|всего|сумма|qty|quantity|unit\s*price|\bitem\b|description|amount|date|дата|invoice|due\s*date|notes?|thank|visa|mastercard|cash|phone|tel|fax|www\.|http)\b"#)
    private static let onlyDate = Rx(#"^(?:\d{1,2}[./-]\d{1,2}[./-]\d{2,4}|\d{4}-\d{2}-\d{2})$"#)
    private static let numeric = Rx(#"^\$?\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?$|^\$?\d+\.\d{2}$|^\$?\d+$"#)

    static func extract(_ lines: [String]) -> [ServiceReceiptLine] {
        var items: [ServiceReceiptLine] = []
        var pending: String?
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || isSkip(line) {
                pending = nil
                continue
            }
            if let parsed = split(line) {
                items.append(parsed)
                pending = nil
            } else if looksLikeDescription(line) {
                pending = line
            } else if let held = pending, let amount = trailingAmount(line), amount > 0 {
                items.append(ServiceReceiptLine(description: held.trimmingCharacters(in: .whitespaces), amount: amount))
                pending = nil
            } else {
                pending = nil
            }
        }
        return items
    }

    private static func isSkip(_ line: String) -> Bool {
        skip.containsMatch(in: line) || onlyDate.matchesWhole(line)
    }

    private static func split(_ line: String) -> ServiceReceiptLine? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        if tokens.count < 2 { return nil }
        var trailing = 0
        for token in tokens.reversed() {
            if !isNumeric(token) { break }
            trailing += 1
        }
        if trailing == 0 { return nil }
        let strip = trailing >= 3 ? 3 : trailing
        let description = tokens.dropLast(strip).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard let amount = DecimalInput.parse(tokens.last ?? ""), amount > 0, looksLikeDescription(description) else {
            return nil
        }
        return ServiceReceiptLine(description: description, amount: amount)
    }

    private static func trailingAmount(_ line: String) -> Double? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        if tokens.isEmpty || tokens.contains(where: { !isNumeric($0) }) { return nil }
        guard let value = DecimalInput.parse(tokens.last ?? ""), value > 0 else { return nil }
        return value
    }

    private static func isNumeric(_ token: String) -> Bool {
        numeric.matchesWhole(token.trimmingCharacters(in: .whitespaces))
    }

    private static func looksLikeDescription(_ text: String) -> Bool {
        if !(2...80).contains(text.count) { return false }
        if isSkip(text) { return false }
        return text.filter(\.isLetter).count >= 2
    }
}

private extension Rx {
    func matchesWhole(_ string: String) -> Bool {
        guard let match = firstMatch(in: string) else { return false }
        return match.range == string.startIndex..<string.endIndex
    }
}

enum ReceiptDates {
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if let iso = Rx(#"(\d{4})-(\d{2})-(\d{2})"#).firstMatch(in: trimmed)?.group(0) { return iso }
        if let eu = Rx(#"(\d{2})\.(\d{2})\.(\d{4})"#).firstMatch(in: trimmed),
           let day = eu.group(1), let month = eu.group(2), let year = eu.group(3) {
            return "\(year)-\(month)-\(day)"
        }
        if let dashed = Rx(#"(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})"#).firstMatch(in: trimmed),
           let aRaw = dashed.group(1), let bRaw = dashed.group(2), let yearRaw = dashed.group(3),
           let a = Int(aRaw), let b = Int(bRaw) {
            let year: Int
            if yearRaw.count == 4 { year = Int(yearRaw) ?? 2000 }
            else if yearRaw.count == 2 { year = 2000 + (Int(yearRaw) ?? 0) }
            else { year = 2000 }
            let month: Int
            let day: Int
            if a > 12 && (1...12).contains(b) {
                month = b
                day = a
            } else if b > 12 && (1...12).contains(a) {
                month = a
                day = b
            } else {
                month = a
                day = b
            }
            if (1...12).contains(month), (1...31).contains(day) {
                return String(format: "%04d-%02d-%02d", year, month, day)
            }
        }
        if let text = normalizeTextMonth(trimmed), !text.isEmpty { return text }
        return ""
    }

    static func normalizeTextMonth(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        let months = [
            "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
            "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
            "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
            "nov": 11, "november": 11, "dec": 12, "december": 12,
        ]
        let mdY = Rx(#"\b(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+(\d{1,2})(?:,)?\s+(\d{2,4})\b"#)
        if let match = mdY.firstMatch(in: trimmed),
           let name = match.group(1), let dayRaw = match.group(2), let yearRaw = match.group(3),
           let month = months[name.lowercased()], let day = Int(dayRaw), (1...31).contains(day) {
            let year = yearRaw.count == 2 ? 2000 + (Int(yearRaw) ?? 0) : (Int(yearRaw) ?? 0)
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
        return ""
    }
}
