import Foundation

/// The one parser for amounts, miles and gallons typed by the driver or read by OCR.
///
/// Port of Android `DecimalInput`. Accepts US `2,500.50`, EU `2.500,50`, decimal comma `25,5`,
/// plain `2500`, an optional `$` / `USD` and spaces.
public enum DecimalInput {

    public static func parse(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let compact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "USD", with: "", options: .caseInsensitive)
            .filter { $0 != "$" && !$0.isWhitespace && $0 != "\u{00A0}" }
        if compact.isEmpty { return nil }
        let negative = compact.hasPrefix("-")
        let body = negative ? String(compact.dropFirst()) : compact
        if body.isEmpty || body.contains(where: { !$0.isNumber && $0 != "," && $0 != "." }) { return nil }
        guard let normalized = normalizeSeparators(body), let value = Double(normalized) else { return nil }
        return negative ? -value : value
    }

    private static func normalizeSeparators(_ body: String) -> String? {
        let lastComma = body.lastIndex(of: ",")
        let lastDot = body.lastIndex(of: ".")
        if let lastComma, let lastDot {
            let decimal: Character = lastComma > lastDot ? "," : "."
            let grouping: Character = decimal == "," ? "." : ","
            if body.firstIndex(of: decimal) != body.lastIndex(of: decimal) { return nil }
            return body.replacingOccurrences(of: String(grouping), with: "").replacingOccurrences(of: String(decimal), with: ".")
        }
        if let lastComma {
            return singleSeparator(body, separator: ",", index: lastComma, singleIsDecimal: digitsAfter(body, lastComma) != 3)
        }
        if let lastDot {
            return singleSeparator(body, separator: ".", index: lastDot, singleIsDecimal: true)
        }
        return body
    }

    private static func singleSeparator(
        _ body: String,
        separator: Character,
        index: String.Index,
        singleIsDecimal: Bool
    ) -> String {
        let count = body.filter { $0 == separator }.count
        let lastIsDecimal = count == 1 ? singleIsDecimal : (1...2).contains(digitsAfter(body, index))
        if !lastIsDecimal { return body.replacingOccurrences(of: String(separator), with: "") }
        let integerPart = body[..<index].replacingOccurrences(of: String(separator), with: "")
        return integerPart + "." + body[body.index(after: index)...]
    }

    private static func digitsAfter(_ body: String, _ index: String.Index) -> Int {
        body.distance(from: body.index(after: index), to: body.endIndex)
    }
}
