import Foundation

/// Fields read from a settlement or pay stub. Net is the amount the driver takes home.
public struct PaycheckParseResult: Equatable, Sendable {
    public var driverName: String?
    public var weekStartDate: String?
    public var weekEndDate: String?
    public var grossAmount: Double?
    public var netAmount: Double
    public var confidence: String
    public var deductionsAmount: Double?

    public init(
        driverName: String?,
        weekStartDate: String?,
        weekEndDate: String?,
        grossAmount: Double?,
        netAmount: Double,
        confidence: String,
        deductionsAmount: Double? = nil
    ) {
        self.driverName = driverName
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.grossAmount = grossAmount
        self.netAmount = netAmount
        self.confidence = confidence
        self.deductionsAmount = deductionsAmount
    }
}

/// Reads a paycheck total out of OCR text, including `4040 30` where the cents lost their dot.
public enum PaycheckTextParser {

    private static let moneyNumber = #"([\d]{1,3}(?:,\d{3})+(?:\.\d{2}|\s+\d{2})?|[\d]{1,3}(?:\s\d{3})+(?:\.\d{2}|\s+\d{2})|[\d]+\.\d{2}|[\d]{3,6}\s+\d{2})"#
    private static let moneyCapture = #"[$S]?\s*"# + moneyNumber
    private static let netPayLabel = #"(?:Net\s*Pay|Зарплата|На\s*руки|К\s*выплате)"#
    private static let statementTakeHomeLabel =
        #"(?:G[ra]{0,2}and\s*Tota[l1I]|Settlement\s*(?:Total|Amount)|Take[\s-]*Home|Check\s*(?:Amount|Total)|Net\s*(?:Settlement|Earnings|Compensation|Amount|Deposit)|Payment\s*Amount)"#
    private static let simpleTakeHomeLabel =
        "(?:\(statementTakeHomeLabel)|Driver\\s*Pay|Net\\s*(?:Check|Earnings)|Amount\\s*(?:to\\s*)?Driver|Total\\s*(?:Due\\s*)?Driver)"
    private static let statementMarker = Rx(
        #"Driver\s*Sett+e?ment|Settlement\s*Summary|Settlement\s*Date|Payee\s*ID|Total\s*Deductions|Owner\s*Operator\s*Sett+e?ment|Weekly\s*Sett+e?ment|Pay\s*Statement|Driver\s*Statement|Compensation\s*Summary|Pay\s*Period|Sett+e?ment"#
    )
    private static let grossPattern = Rx(
        #"(?:Gross\s*(?:Pay(?:\s*Total)?|Earnings|Compensation|Amount)|Total\s*(?:Earnings|Compensation|Gross))[^\d$]{0,40}[$S]?\s*"# + moneyNumber,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let driverPattern = Rx(#"(?:Driver(?:\s*Name)?|Contractor(?:\s*Name)?|Employee(?:\s*Name)?)\s*[:]\s*([A-Za-z .'-]{2,60})"#)
    private static let weekStartPattern = Rx(#"(?:Week\s*Start|Period\s*(?:Start|Beginning|Begin)|Cutoff\s*Date|Week\s*(?:Beginning|Of))\s*[:\s]*([^\n]+)"#)
    private static let weekEndPattern = Rx(#"(?:Week\s*End(?:ing)?|Period\s*End(?:ing)?)\s*[:\s]*([^\n]+)"#)
    private static let periodRangePattern = Rx(#"(?:Pay\s*Period|Settlement\s*Period|Statement\s*Period)\s*[:\s]*([^\n]+)"#)
    private static let periodDateToken = Rx(#"\b(\d{4}-\d{2}-\d{2}|\d{1,2}[./-]\d{1,2}[./-]\d{2,4})\b"#, options: [])
    private static let fileWeekRange = Rx(#"(\d{1,2}[./]\d{1,2})[-–](\d{1,2}[./]\d{1,2})"#, options: [])
    private static let methodNet = Rx(#"\d{1,3}\s*%[^\d$]{0,12}[$S]?\s*"# + moneyNumber, options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let totalLine = Rx(#"(?m)^[^\n]{0,48}\bTotal\b[^\n]{0,48}[$S]?\s*"# + moneyNumber)
    private static let deductionOrGross = Rx(#"deduct|gross|miles|load"#)

    public static func looksLikePaycheck(_ text: String, fileName: String? = nil) -> Bool {
        let hay = haystack(text, fileName: fileName)
        return amountAfter(hay, simpleTakeHomeLabel) != nil ||
            amountAfter(hay, netPayLabel) != nil ||
            (isDriverStatement(hay) && computedTakeHome(hay) != nil)
    }

    public static func parse(
        _ text: String,
        fileName: String? = nil,
        defaultYear: Int = Calendar.current.component(.year, from: Date())
    ) -> PaycheckParseResult? {
        let hay = haystack(text, fileName: fileName)
        let statement = isDriverStatement(hay)
        let takeHome = amountAfter(hay, statement ? statementTakeHomeLabel : simpleTakeHomeLabel)
        let netPays = amountsAfter(hay, netPayLabel)
        let computed = statement ? computedTakeHome(hay) : nil
        let netAmount: Double?
        if statement, let takeHome {
            netAmount = takeHome
        } else if !statement, let first = netPays.first {
            netAmount = first
        } else if let takeHome {
            netAmount = takeHome
        } else if statement {
            netAmount = computed
        } else {
            netAmount = nil
        }
        guard let netAmount, netAmount > 0 else { return nil }

        let grossAmount = labeledMoney(hay, grossPattern)
        let periodDates = periodRangePattern.firstMatch(in: hay).map { datesIn($0.groupOrEmpty(1), defaultYear: defaultYear) } ?? []
        let fileWeek = weekFromFileName(fileName, defaultYear: defaultYear)
        let weekStart = normalized(weekStartPattern.firstMatch(in: hay)?.group(1), defaultYear: defaultYear)
            ?? periodDates.first
            ?? fileWeek?.0
        let weekEnd = normalized(weekEndPattern.firstMatch(in: hay)?.group(1), defaultYear: defaultYear)
            ?? periodDates.dropFirst().first
            ?? fileWeek?.1
        let driverName = driverPattern.firstMatch(in: text)?.group(1)
        let deductions = amountAfter(hay, #"Total\s*Deductions"#)
        let confidence = (grossAmount != nil && deductions != nil) || (grossAmount != nil && abs((grossAmount ?? 0) - netAmount) > 0.009)
            ? "high"
            : "medium"

        return PaycheckParseResult(
            driverName: driverName,
            weekStartDate: weekStart,
            weekEndDate: weekEnd,
            grossAmount: grossAmount,
            netAmount: netAmount,
            confidence: confidence,
            deductionsAmount: deductions
        )
    }

    static func isDriverStatement(_ text: String) -> Bool {
        statementMarker.containsMatch(in: text) || amountsAfter(text, netPayLabel).count >= 2
    }

    private static func haystack(_ text: String, fileName: String?) -> String {
        [fileName?.replacingOccurrences(of: "-", with: " "), text].compactMap { $0 }.joined(separator: "\n")
    }

    private static func computedTakeHome(_ hay: String) -> Double? {
        guard let deductions = amountAfter(hay, #"Total\s*Deductions"#) else { return nil }
        guard let loadsNet = statementLoadsNet(hay) ?? lineNetSum(hay) else { return nil }
        let net = ((loadsNet - deductions) * 100).rounded() / 100
        return net > 0 ? net : nil
    }

    private static func statementLoadsNet(_ hay: String) -> Double? {
        totalLine.matches(in: hay).compactMap { match -> Double? in
            if deductionOrGross.containsMatch(in: match.groupOrEmpty(0)) { return nil }
            let value = parsePayMoney(match.group(1))
            return value > 50 ? value : nil
        }.first
    }

    private static func lineNetSum(_ hay: String) -> Double? {
        let nets = methodNet.matches(in: hay).compactMap { match -> Double? in
            let value = parsePayMoney(match.group(1))
            return value > 0 ? value : nil
        }
        guard nets.count >= 2 else { return nil }
        return (nets.reduce(0, +) * 100).rounded() / 100
    }

    private static func amountAfter(_ text: String, _ label: String) -> Double? {
        amountsAfter(text, label).first
    }

    private static func amountsAfter(_ text: String, _ label: String) -> [Double] {
        let pattern = label + #"[^\d$]{0,80}"# + moneyCapture
        let regex = Rx(pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        return regex.matches(in: text).compactMap { match in
            let value = parsePayMoney(match.group(1))
            return value > 0 ? value : nil
        }
    }

    private static func labeledMoney(_ text: String, _ pattern: Rx) -> Double? {
        guard let raw = pattern.firstMatch(in: text)?.group(1) else { return nil }
        let value = parsePayMoney(raw)
        return value > 0 ? value : nil
    }

    /// `4040 30` / `4 040 30` → 4040.30. Otherwise a normal money parse.
    static func parsePayMoney(_ raw: String?) -> Double {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return 0 }
        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        if let cents = parts.last, parts.count >= 2, cents.count == 2, cents.allSatisfy(\.isNumber), !trimmed.contains(".") {
            let dollars = Double(parts.dropLast().joined().replacingOccurrences(of: ",", with: ""))
            if let dollars, let centsValue = Int(cents) {
                return dollars + Double(centsValue) / 100
            }
        }
        return DecimalInput.parse(trimmed) ?? 0
    }

    private static func datesIn(_ raw: String, defaultYear: Int) -> [String] {
        periodDateToken.matches(in: raw).compactMap { match in
            let normalized = ReceiptDateParser.normalize(match.group(1), defaultYear: defaultYear)
            return normalized.count >= 10 ? normalized : nil
        }
    }

    private static func weekFromFileName(_ fileName: String?, defaultYear: Int) -> (String, String)? {
        guard let match = fileWeekRange.firstMatch(in: fileName ?? "") else { return nil }
        let start = ReceiptDateParser.normalize(match.group(1)?.replacingOccurrences(of: ".", with: "/"), defaultYear: defaultYear)
        let end = ReceiptDateParser.normalize(match.group(2)?.replacingOccurrences(of: ".", with: "/"), defaultYear: defaultYear)
        guard !start.isEmpty, !end.isEmpty else { return nil }
        return (start, end)
    }

    private static func normalized(_ raw: String?, defaultYear: Int) -> String? {
        let value = ReceiptDateParser.normalize(raw, defaultYear: defaultYear)
        return value.count >= 10 ? value : nil
    }
}

/// Net amount for paycheck edit and add forms.
public enum PaycheckSalaryFields {
    public enum FormError: Equatable, Sendable { case net }

    public static func parseAmount(_ raw: String) -> Double? {
        DecimalInput.parse(raw).flatMap { $0 > 0 ? $0 : nil }
    }

    public static func validate(netText: String) -> FormError? {
        parseAmount(netText) == nil ? .net : nil
    }

    public static func formatAmount(_ amount: Double) -> String {
        amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(amount))
            : String(format: "%.2f", amount)
    }
}
