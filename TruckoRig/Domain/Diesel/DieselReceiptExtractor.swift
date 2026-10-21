import Foundation

/// Optional fields read from a pump display or paper fuel receipt. Missing values stay nil.
public struct DieselReceiptFields: Equatable, Sendable {
    public var gallons: Double?
    public var pricePerGallon: Double?
    public var discountPricePerGallon: Double?
    public var totalAmount: Double?
    public var location: String?
    public var vendor: String?

    public init(
        gallons: Double? = nil,
        pricePerGallon: Double? = nil,
        discountPricePerGallon: Double? = nil,
        totalAmount: Double? = nil,
        location: String? = nil,
        vendor: String? = nil
    ) {
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.discountPricePerGallon = discountPricePerGallon
        self.totalAmount = totalAmount
        self.location = location
        self.vendor = vendor
    }

    public var hasAnyField: Bool {
        gallons != nil || pricePerGallon != nil || discountPricePerGallon != nil ||
            totalAmount != nil || !(location ?? "").isEmpty || !(vendor ?? "").isEmpty
    }
}

/// Best-effort OCR harvest for diesel gallons and price per gallon.
///
/// Unlike `DieselTextParser`, this does not require a fuel keyword plus a labeled total —
/// pump screens often show only gallons and price.
public enum DieselReceiptExtractor {

    private static let fuelProduct = Rx(#"diesel|ulsd|#2|fuel|топлив|дизел|reefer"#)
    private static let gallonsInline = [
        Rx(#"([\d]{1,3}(?:[.,]\d{1,4})?)[ \t]*(?:gal(?:lons?)?|gals?|гл)\b"#),
        Rx(
            #"(?:^|[\n\s])(?:gallons?|gals?|sale\s*gals?|volume|объем|галлоны?)\s*[:\-]?\s*\$?\s*([\d]{1,3}(?:[.,]\d{1,4})?)"#,
            options: [.caseInsensitive, .anchorsMatchLines]
        ),
        Rx(#"([\d]{1,3}(?:[.,]\d{1,4})?)[ \t]+G(?:AL)?S?\b"#),
    ]
    private static let qtyInline = [
        Rx(#"(?:qty|quantity)\s*[:\-]?\s*([\d]{1,3}(?:[.,]\d{1,4})?)"#),
    ]
    private static let ppgInline = [
        Rx(#"(?:price\s*/?\s*gal(?:lon)?s?|price\s*per\s*gal(?:lon)?s?|ppg|ppu|unit\s*price|\$\s*/\s*gal|цена\s*за\s*гал(?:лон)?)\s*[:\-]?\s*\$?\s*([\d]{1,2}(?:[.,]\d{1,4})?)"#),
        Rx(#"(?:Price|PPG|PPU|@\s*)\$?\s*([\d.]+)\s*(?:/|\s*per\s*)?\s*g(?:al)?"#),
        Rx(#"\$\s*([\d]{1,2}\.\d{2,3})\s*/\s*g(?:al)?"#),
    ]
    private static let discountInline = [
        Rx(#"(?:disc(?:ount)?(?:ed)?\s*(?:price|ppg)|fleet\s*price|cash\s*price|цена\s*со\s*скидкой)\s*[:\-]?\s*\$?\s*([\d]{1,2}(?:[.,]\d{1,4})?)"#),
    ]
    private static let totalInline = [
        Rx(#"(?:Total\s*Amount|Amount\s*Due|Fuel\s*Total|Diesel\s*Total|Pump\s*Total|Fuel\s*(?:Sale|Amount)|Sale\s*(?:Amount|Total)|Итого)\s*[:\s]*\$?\s*([\d,]+\.?\d*)"#),
        Rx(
            #"^\s*(?:Total|SALE|AMT|AMOUNT)\s*[:\s]*\$?\s*([\d,]+\.?\d*)\s*$"#,
            options: [.caseInsensitive, .anchorsMatchLines]
        ),
    ]
    private static let locationInline = [
        Rx(#"(?:Location|Store|Station|АЗС)\s*[:\s]*([^\n]+)"#),
        Rx(#"(?:Merchant|Vendor)\s*[:\s]*([^\n]+)"#),
    ]
    private static let cityState = Rx(
        #"\b([A-Z][A-Za-z]+(?:[\s\-'][A-Z][A-Za-z]+)*)\,\s*([A-Z]{2})(?:\s+\d{5}(?:-\d{4})?)?\b"#,
        options: []
    )
    private static let explicitGallonsCue = Rx(#"gallons?|gals?|sale\s*gals?|volume|объем|галлон"#)
    private static let qtyCue = Rx(#"\bqty\b|quantity"#)
    private static let ppgCue = Rx(#"price\s*/?\s*gal|price\s*per\s*gal|ppg|ppu|unit\s*price|\$\s*/\s*g|цена\s*за\s*гал"#)
    private static let discountCue = Rx(#"disc(?:ount)?|fleet\s*price|cash\s*price|скидк"#)
    private static let totalCue = Rx(#"total|amount\s*due|итого|pump\s*total|fuel\s*sale|fuel\s*amount|sale\s*amount|\bsale\b|\bamt\b"#)
    private static let numberToken = Rx(#"\$?\s*([\d]{1,4}(?:[.,]\d{1,4})?)"#)
    private static let fuelGrade = Rx(#"#\s*\d|\bgrade\b"#)

    private static let knownStops: [(Rx, String)] = [
        (Rx(#"love'?s"#), "Love's Travel Stop"),
        (Rx(#"flying\s*j"#), "Flying J"),
        (Rx(#"\bpilot\b"#), "Pilot"),
        (Rx(#"travelcenters|\bta\s*express\b|\bta\b"#), "TA"),
        (Rx(#"\bpetro\b"#), "Petro"),
        (Rx(#"speedway"#), "Speedway"),
        (Rx(#"maverik"#), "Maverik"),
        (Rx(#"quik\s*trip|\bqt\b"#), "QuikTrip"),
        (Rx(#"race\s*trac"#), "RaceTrac"),
        (Rx(#"circle\s*k"#), "Circle K"),
        (Rx(#"sheetz"#), "Sheetz"),
        (Rx(#"wawa"#), "Wawa"),
        (Rx(#"thornton"#), "Thorntons"),
        (Rx(#"kum\s*[&n]\s*go"#), "Kum & Go"),
        (Rx(#"sapp\s*bros"#), "Sapp Bros"),
        (Rx(#"ambest"#), "Ambest"),
    ]

    private static let gradeGallonsMax = 9.0
    private static let gallonsRange = 0.1...400.0
    private static let ppgRange = 0.5...12.0
    private static let totalRange = 1.0...8_000.0

    public static func extract(_ text: String) -> DieselReceiptFields {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return DieselReceiptFields() }

        var gallons = firstPositive(raw, gallonsInline, asGallons)
        if gallons == nil && fuelProduct.containsMatch(in: raw) {
            gallons = firstPositive(raw, qtyInline, asGallons)
        }
        var ppg = firstPositive(raw, ppgInline, asPpg)
        var discount = firstPositive(raw, discountInline, asPpg)
        var total = firstPositive(raw, totalInline) { asTotal(DecimalInput.parse($0) ?? 0) }

        let lines = raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let adjacent = harvestAdjacent(lines)
        if gallons == nil { gallons = adjacent.gallons }
        if ppg == nil { ppg = adjacent.ppg }
        if discount == nil { discount = adjacent.discount }
        if total == nil { total = adjacent.total }

        if gallons == nil, let total, let ppg, ppg > 0 {
            gallons = asGallons(total / ppg)
        }
        if ppg == nil, let total, let gallons, gallons > 0 {
            ppg = asPpg(total / gallons)
        }

        let vendor = findVendor(raw)
        let labeledLocation = Rx.firstCapture(in: raw, patterns: locationInline)?.trimmingCharacters(in: .whitespaces)
        let cityStateLine = cityState.firstMatch(in: raw)?.groupOrEmpty(0).trimmingCharacters(in: .whitespaces)
        let location = buildLocation(labeled: labeledLocation, vendor: vendor, cityStateLine: cityStateLine)

        return reconcile(
            DieselReceiptFields(
                gallons: gallons,
                pricePerGallon: ppg,
                discountPricePerGallon: discount,
                totalAmount: total,
                location: location?.isEmpty == false ? location : nil,
                vendor: vendor
            ),
            text: raw
        )
    }

    /// Gallons times price must land on the total. A grade such as diesel #2 is not a gallon count.
    public static func reconcile(_ fields: DieselReceiptFields, text: String) -> DieselReceiptFields {
        guard let gallons = fields.gallons else { return fields }
        guard let price = fields.pricePerGallon ?? fields.discountPricePerGallon else { return fields }
        guard let total = fields.totalAmount else { return fields }
        var copy = fields
        if close(gallons * price, total) {
            if copy.pricePerGallon == nil { copy.pricePerGallon = price }
            return copy
        }
        if let discount = fields.discountPricePerGallon, fields.pricePerGallon != nil, close(gallons * discount, total) {
            copy.pricePerGallon = discount
            return copy
        }
        let grade = gallons <= gradeGallonsMax && fuelGrade.containsMatch(in: text)
        guard grade else { return fields }
        copy.gallons = asGallons(total / price)
        return copy
    }

    public static func formatField(_ value: Double, maxDecimals: Int = 3) -> String {
        let text = String(format: "%.\(maxDecimals)f", value)
        var trimmed = text
        while trimmed.contains(".") && (trimmed.hasSuffix("0") || trimmed.hasSuffix(".")) {
            trimmed.removeLast()
        }
        return trimmed
    }

    private static func close(_ product: Double, _ total: Double) -> Bool {
        let gap = abs(product - total)
        return gap <= 0.75 || gap <= total * 0.02
    }

    private static func harvestAdjacent(_ lines: [String]) -> (gallons: Double?, ppg: Double?, discount: Double?, total: Double?) {
        var gallons: Double?
        var ppg: Double?
        var discount: Double?
        var total: Double?
        for index in lines.indices {
            let line = lines[index]
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            let previous = index > 0 ? lines[index - 1] : ""
            let afterNext = index + 2 < lines.count ? lines[index + 2] : ""
            let here = firstNumber(line)
            let below = firstNumber(next)
            if isGallonsLine(line, previous: previous, next: next), let below, gallons == nil {
                gallons = asGallons(below)
            } else if isGallonsLine(next, previous: line, next: afterNext), let here, gallons == nil {
                gallons = asGallons(here)
            }
            if isPpgLine(line), let below, ppg == nil { ppg = asPpg(below) }
            if isPpgLine(next), let here, ppg == nil { ppg = asPpg(here) }
            if isDiscountLine(line), let below, discount == nil { discount = asPpg(below) }
            if isTotalLine(line), let below, total == nil { total = asTotal(below) }
        }
        return (gallons, ppg, discount, total)
    }

    private static func findVendor(_ text: String) -> String? {
        for (pattern, label) in knownStops where pattern.containsMatch(in: text) {
            return label
        }
        let labeled = Rx.firstCapture(in: text, patterns: locationInline)?.trimmingCharacters(in: .whitespaces)
        if let labeled, !labeled.isEmpty, !labeled.lowercased().contains("location") {
            return labeled
        }
        return nil
    }

    private static func buildLocation(labeled: String?, vendor: String?, cityStateLine: String?) -> String? {
        var parts: [String] = []
        if let vendor, !vendor.isEmpty { parts.append(vendor) }
        if let labeled {
            let trimmed = labeled.trimmingCharacters(in: .whitespaces)
            let repeatsVendor = vendor != nil && trimmed.range(of: vendor ?? "", options: .caseInsensitive) != nil
            if !trimmed.isEmpty && !repeatsVendor { parts.append(trimmed) }
        }
        if let cityStateLine, !cityStateLine.isEmpty { parts.append(cityStateLine) }
        var seen = Set<String>()
        let unique = parts.filter { seen.insert($0).inserted }
        let joined = unique.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private static func firstPositive(_ text: String, _ patterns: [Rx], _ convert: (String) -> Double?) -> Double? {
        guard let raw = Rx.firstCapture(in: text, patterns: patterns) else { return nil }
        return convert(raw)
    }

    private static func firstNumber(_ line: String) -> Double? {
        guard let raw = numberToken.firstMatch(in: line)?.group(1) else { return nil }
        return DecimalInput.parse(raw).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func isGallonsLine(_ line: String, previous: String, next: String) -> Bool {
        if ppgCue.containsMatch(in: line) { return false }
        if explicitGallonsCue.containsMatch(in: line) { return true }
        if !qtyCue.containsMatch(in: line) { return false }
        return fuelProduct.containsMatch(in: line) || fuelProduct.containsMatch(in: previous) || fuelProduct.containsMatch(in: next)
    }

    private static func isPpgLine(_ line: String) -> Bool { ppgCue.containsMatch(in: line) }

    private static func isDiscountLine(_ line: String) -> Bool {
        discountCue.containsMatch(in: line) && !isPpgLine(line) && !explicitGallonsCue.containsMatch(in: line)
    }

    private static func isTotalLine(_ line: String) -> Bool {
        totalCue.containsMatch(in: line) && !explicitGallonsCue.containsMatch(in: line) && !isPpgLine(line)
    }

    private static func asGallons(_ value: Double) -> Double? { gallonsRange.contains(value) ? value : nil }
    private static func asGallons(_ raw: String) -> Double? {
        guard let value = DecimalInput.parse(raw) else { return nil }
        return asGallons(value)
    }
    private static func asPpg(_ value: Double) -> Double? { ppgRange.contains(value) ? value : nil }
    private static func asPpg(_ raw: String) -> Double? {
        guard let value = DecimalInput.parse(raw) else { return nil }
        return asPpg(value)
    }
    private static func asTotal(_ value: Double) -> Double? { totalRange.contains(value) ? value : nil }
}
