import Foundation

/// A diesel receipt that cleared the fuel cue and produced a positive total.
public struct DieselParseResult: Equatable, Sendable {
    public var date: String?
    public var totalAmount: Double
    public var gallons: Double?
    public var pricePerGallon: Double?
    public var discountPricePerGallon: Double?
    public var location: String?
    public var vendor: String?
    public var confidence: String

    public init(
        date: String?,
        totalAmount: Double,
        gallons: Double?,
        pricePerGallon: Double?,
        discountPricePerGallon: Double? = nil,
        location: String?,
        vendor: String?,
        confidence: String
    ) {
        self.date = date
        self.totalAmount = totalAmount
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.discountPricePerGallon = discountPricePerGallon
        self.location = location
        self.vendor = vendor
        self.confidence = confidence
    }
}

/// Turns OCR text into a diesel fill. Bare "Total" is ignored so Relay miles are not a fuel amount.
public enum DieselTextParser {

    private static let totalPatterns = [
        Rx(#"(?:Total\s*Amount|Amount\s*Due|Итого)\s*[:\s]*\$?\s*([\d,]+\.?\d*)"#),
        Rx(#"(?:Fuel\s*Total|Diesel\s*Total|Pump\s*Total|Fuel\s*(?:Sale|Amount)|Sale\s*(?:Amount|Total))\s*[:\s]*\$?\s*([\d,]+\.?\d*)"#),
        Rx(
            #"^\s*(?:SALE|AMT|AMOUNT)\s*[:\s]*\$?\s*([\d,]+\.?\d*)\s*$"#,
            options: [.caseInsensitive, .anchorsMatchLines]
        ),
    ]
    private static let gallonsPattern = Rx(#"([\d.]+)[ \t]*(?:gal|gallons|gals|гл)\b"#)
    private static let ppgPattern = Rx(#"(?:Price|PPG|PPU|@\s*)\$?\s*([\d.]+)\s*(?:/|\s*per\s*)?\s*g(?:al)?"#)
    private static let datePattern = Rx(#"(?:Date|Дата|Trans(?:action)?\s*Date)\s*[:\s]*([^\n]+)"#)
    private static let unlabeledDate = Rx(#"\b(\d{1,2}[./-]\d{1,2}[./-]\d{2,4})\b"#)
    private static let locationPattern = Rx(#"(?:Location|Store|Station|City|АЗС)\s*[:\s]*([^\n]+)"#)
    private static let vendorPattern = Rx(#"(?:Merchant|Vendor)\s*[:\s]*([^\n]+)"#)
    private static let fuelCue = Rx(#"diesel|fuel|gallons?|gal\b|топлив|дизел|\bdef\b|ad[\s\-]?blue|ulsd|#2\s*diesel|pump\s*total"#)

    public static func looksLikeDiesel(_ text: String) -> Bool { parse(text) != nil }

    public static func parse(_ text: String, defaultYear: Int = Calendar.current.component(.year, from: Date())) -> DieselParseResult? {
        labeled(text, defaultYear: defaultYear) ?? fromReceiptFields(text, defaultYear: defaultYear)
    }

    private static func labeled(_ text: String, defaultYear: Int) -> DieselParseResult? {
        guard fuelCue.containsMatch(in: text) else { return nil }
        guard totalPatterns.contains(where: { $0.containsMatch(in: text) }) else { return nil }
        guard let totalRaw = Rx.firstCapture(in: text, patterns: totalPatterns) else { return nil }
        let totalAmount = DecimalInput.parse(totalRaw) ?? 0
        guard totalAmount > 0 else { return nil }
        let extra = DieselReceiptExtractor.extract(text)
        let gallons = extra.gallons ?? gallonsPattern.firstMatch(in: text).flatMap { DecimalInput.parse($0.groupOrEmpty(1)) }
        let ppg = extra.pricePerGallon ?? ppgPattern.firstMatch(in: text).flatMap { DecimalInput.parse($0.groupOrEmpty(1)) }
        return DieselParseResult(
            date: findDate(text, defaultYear: defaultYear),
            totalAmount: totalAmount,
            gallons: gallons,
            pricePerGallon: ppg,
            discountPricePerGallon: extra.discountPricePerGallon,
            location: locationPattern.firstMatch(in: text)?.group(1) ?? extra.location,
            vendor: vendorPattern.firstMatch(in: text)?.group(1) ?? extra.vendor,
            confidence: "high"
        )
    }

    private static func fromReceiptFields(_ text: String, defaultYear: Int) -> DieselParseResult? {
        let fields = DieselReceiptExtractor.extract(text)
        let total = fields.totalAmount ?? derivedTotal(fields.gallons, fields.pricePerGallon ?? fields.discountPricePerGallon)
        guard let total, total > 0 else { return nil }
        let hasCue = fuelCue.containsMatch(in: text) || fields.vendor != nil || fields.gallons != nil
        guard hasCue else { return nil }
        let confident = fields.gallons != nil && fields.pricePerGallon != nil
        return DieselParseResult(
            date: findDate(text, defaultYear: defaultYear),
            totalAmount: total,
            gallons: fields.gallons,
            pricePerGallon: fields.pricePerGallon ?? fields.discountPricePerGallon,
            discountPricePerGallon: fields.discountPricePerGallon,
            location: fields.location,
            vendor: fields.vendor,
            confidence: confident ? "high" : "medium"
        )
    }

    private static func derivedTotal(_ gallons: Double?, _ ppg: Double?) -> Double? {
        guard let gallons, let ppg, gallons > 0, ppg > 0 else { return nil }
        return gallons * ppg
    }

    private static func findDate(_ text: String, defaultYear: Int) -> String? {
        if let raw = datePattern.firstMatch(in: text)?.group(1) {
            let normalized = ReceiptDateParser.normalize(raw, defaultYear: defaultYear)
            if normalized.count >= 10 { return normalized }
        }
        if let raw = unlabeledDate.firstMatch(in: text)?.group(0) {
            let normalized = ReceiptDateParser.normalize(raw, defaultYear: defaultYear)
            if normalized.count >= 10 { return normalized }
        }
        return nil
    }
}
