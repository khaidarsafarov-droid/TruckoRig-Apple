import Foundation

/// Decides whether shared text is a load. Field values come from the same inbound parsers the
/// journal already uses; this type only scores the signals and refuses weak matches.
///
/// Points, capped so a pile of keywords cannot pass on its own:
/// rate 25, each city 15, a date 10, miles 5, keywords 5 each up to 25.
/// Accept at 55, which is a rate plus both cities, or a rate plus one city and several other signals.
/// A high score with blank fields is still a load. A low score adds nothing.
public enum ShareLoadClassifier {
    public static let acceptScore = 55
    public static let maxLoads = 20

    public static func classify(
        text: String,
        fileName: String? = nil,
        reference: Date = Date()
    ) -> ShareLoadVerdict {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected(.empty) }

        let haystack = [fileName?.replacingOccurrences(of: "-", with: " "), trimmed]
            .compactMap { $0 }
            .joined(separator: "\n")
        let keywords = keywordScore(haystack)
        var signals = extract(trimmed, keywords: keywords, reference: reference)
        mergeParser(into: &signals, text: trimmed, fileName: fileName, reference: reference)

        let kind = ReceiptKindClassifier.classify(trimmed, fileName: fileName)
        let strongLoad = keywords.confirmation
            || (!signals.origin.isEmpty && !signals.destination.isEmpty && signals.rate > 0 && keywords.points >= 10)
        if (kind == .diesel || kind == .def || kind == .paycheck) && !strongLoad {
            return .rejected(.otherDocument)
        }

        let score = score(signals, keywordPoints: keywords.points)
        guard signals.rate > 0,
              !signals.origin.isEmpty || !signals.destination.isEmpty,
              score >= acceptScore else {
            return .rejected(.notALoad)
        }

        let parsed = InboundLoadParser.parseAll(trimmed, fileName: fileName, reference: reference)
        if parsed.count >= 2 {
            let many = parsed.prefix(maxLoads).compactMap { load in
                fields(from: load, document: signals, score: score, text: trimmed)
            }
            if !many.isEmpty {
                return .accepted(many)
            }
        }
        return .accepted([makeFields(signals, score: score, text: trimmed)])
    }

    // MARK: - Signals

    private struct Signals {
        var tripId = ""
        var synthesizedTrip = false
        var broker = ""
        var origin = ""
        var destination = ""
        var pickupDate: Date?
        var deliveryDate: Date?
        var rate: Double = 0
        var miles: Double = 0
    }

    private struct Keywords {
        var points: Int
        var confirmation: Bool
    }

    private static let keywordGroups: [(confirmation: Bool, Rx)] = [
        (true, Rx(#"rate\s*conf|rate\s*con\b|ratecon|load\s*conf|load\s*tender"#)),
        (false, Rx(#"dispatch\s*info|\bdispatch\b"#)),
        (false, Rx(#"load\s*(?:#|no\.?|number|id)|trip\s*id|confirmation\s*(?:#|number)|pro\s*#"#)),
        (false, Rx(#"\bP\.?O\.?\b|purchase\s*order"#)),
        (false, Rx(#"\bshipper\b"#)),
        (false, Rx(#"\bconsignee\b"#)),
        (false, Rx(#"\bpick\s*up\b|\bpickup\b|pu[\s\-]*address"#)),
        (false, Rx(#"\bdeliver(?:y|ies)\b|del[\s\-]*address"#)),
        (false, Rx(#"\bbroker\b"#)),
        (false, Rx(#"\bMC\s*#|motor\s*carrier"#)),
        (false, Rx(#"\bcarrier\b"#)),
    ]

    private static let ratePatterns: [Rx] = [
        Rx(#"Total\s*Rate\s*[:\s]*\$?\s*([\d.,]+)"#),
        Rx(#"Line\s*-?\s*Haul(?:\s*Rate)?\s*[:\s]*\$?\s*([\d.,]+)"#),
        Rx(#"Estimated\s*Rate(?:[^$\n]{0,48})\$\s*([\d,]+(?:\.\d{2})?)"#),
        Rx(#"All[\s-]?in(?:\s*rate)?\s*[:\s]*\$?\s*([\d.,]+)"#),
        Rx(#"(?:Flat|Load)\s*Rate\s*[:\s]*\$?\s*([\d.,]+)"#),
        Rx(#"(?:Rate|Pay|Оплата|Ставка)\s*[:\s]*\$?\s*([\d.,]+)"#),
    ]

    private static let bareMoney = Rx(#"\$\s*([\d,]+\.\d{2})\b"#)
    private static let milePatterns: [Rx] = [
        Rx(#"Total\s*(?:Loaded\s*)?Miles\s*[:\s]*([\d.,]+)"#),
        Rx(#"(?:Loaded\s*Miles|Miles|Distance)\s*[:\s]*([\d.,]+)"#),
        Rx(#"([\d.,]+)\s*miles?\b"#),
    ]
    private static let tripPatterns: [Rx] = [
        Rx(#"(?:Load|Trip|PRO|Confirmation|Order)\s*(?:#|No\.?|Number|ID)\s*[:#]?\s*([A-Z0-9][A-Z0-9\-]{2,})"#),
        Rx(#"\bPO\s*#?\s*[:#]?\s*([A-Z0-9][A-Z0-9\-]{2,})"#),
        Rx(#"\b(T-[A-Z0-9]{5,})\b"#),
    ]
    private static let cityState = Rx(
        #"\b([A-Za-z][A-Za-z .'\-]{1,40}?),\s*([A-Za-z]{2})\b(?:\s+(\d{5}(?:-\d{4})?))?"#
    )
    private static let canadian: Set<String> = [
        "AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT",
    ]

    private static func keywordScore(_ text: String) -> Keywords {
        var points = 0
        var confirmation = false
        for group in keywordGroups where group.1.containsMatch(in: text) {
            points += 5
            if group.confirmation { confirmation = true }
        }
        return Keywords(points: min(25, points), confirmation: confirmation)
    }

    private static func extract(_ text: String, keywords: Keywords, reference: Date) -> Signals {
        var signals = Signals()
        signals.rate = labeledRate(text)
        if signals.rate <= 0, keywords.points >= 10, let bare = bareMoney.firstMatch(in: text)?.group(1) {
            signals.rate = NumberParsing.parseMoney(bare)
        }
        signals.broker = broker(in: text)
        signals.tripId = tripId(in: text)
        signals.origin = labeledPlace(text, labels: ["shipper", "pick up", "pickup", "pu-address", "pu address", "origin"]) ?? ""
        signals.destination = labeledPlace(text, labels: ["consignee", "delivery", "del-address", "del address", "destination"]) ?? ""
        let places = allPlaces(text)
        if signals.origin.isEmpty, let first = places.first { signals.origin = first }
        if signals.destination.isEmpty {
            signals.destination = places.first { !samePlace($0, signals.origin) } ?? ""
        }
        if signals.origin == signals.destination { signals.destination = "" }
        let dates = dates(in: text, reference: reference)
        signals.pickupDate = dates.pickup
        signals.deliveryDate = dates.delivery
        let milesRaw = Rx.firstCapture(in: text, patterns: milePatterns).map(NumberParsing.parseMiles) ?? 0
        signals.miles = NumberParsing.sanitizeLoadedMiles(milesRaw, totalRate: signals.rate)
        return signals
    }

    private static func mergeParser(
        into signals: inout Signals,
        text: String,
        fileName: String?,
        reference: Date
    ) {
        guard let parsed = InboundLoadParser.parseAll(text, fileName: fileName, reference: reference).first else { return }
        if signals.rate <= 0 { signals.rate = parsed.totalRate }
        if signals.miles <= 0 { signals.miles = parsed.totalMiles }
        if signals.origin.isEmpty, plausible(parsed.pointA) { signals.origin = parsed.pointA }
        if signals.destination.isEmpty, plausible(parsed.pointB) { signals.destination = parsed.pointB }
        if signals.tripId.isEmpty, let trip = cleanedTrip(parsed.tripId) {
            signals.tripId = trip
        }
    }

    private static func score(_ signals: Signals, keywordPoints: Int) -> Int {
        var total = keywordPoints
        if signals.rate > 0 { total += 25 }
        if !signals.origin.isEmpty { total += 15 }
        if !signals.destination.isEmpty { total += 15 }
        if signals.pickupDate != nil || signals.deliveryDate != nil { total += 10 }
        if signals.miles > 0 { total += 5 }
        return total
    }

    private static func makeFields(_ signals: Signals, score: Int, text: String) -> ShareLoadFields {
        var copy = signals
        if copy.tripId.isEmpty || isGeneratedTrip(copy.tripId) {
            copy.tripId = "S-" + String(fnv(text).prefix(8)).uppercased()
            copy.synthesizedTrip = true
        }
        return ShareLoadFields(
            tripId: TripID.normalize(copy.tripId),
            broker: copy.broker,
            origin: copy.origin,
            destination: copy.destination,
            pickupDate: copy.pickupDate,
            deliveryDate: copy.deliveryDate,
            rate: copy.rate,
            miles: copy.miles,
            missing: missing(copy),
            score: score
        )
    }

    private static func fields(from load: ParsedLoad, document: Signals, score: Int, text: String) -> ShareLoadFields? {
        let origin = plausible(load.pointA) ? load.pointA : ""
        let destination = plausible(load.pointB) ? load.pointB : ""
        guard load.totalRate > 0, !origin.isEmpty || !destination.isEmpty else { return nil }
        var trip = cleanedTrip(load.tripId) ?? ""
        var synthesized = false
        if trip.isEmpty {
            trip = "S-" + String(fnv(text + "\n" + load.tripId).prefix(8)).uppercased()
            synthesized = true
        }
        let signals = Signals(
            tripId: trip,
            synthesizedTrip: synthesized,
            broker: document.broker,
            origin: origin,
            destination: destination,
            pickupDate: document.pickupDate,
            deliveryDate: document.deliveryDate,
            rate: load.totalRate,
            miles: load.totalMiles
        )
        return ShareLoadFields(
            tripId: trip,
            broker: document.broker,
            origin: origin,
            destination: destination,
            pickupDate: document.pickupDate,
            deliveryDate: document.deliveryDate,
            rate: load.totalRate,
            miles: load.totalMiles,
            missing: missing(signals),
            score: score
        )
    }

    private static func missing(_ signals: Signals) -> [ShareLoadMissing] {
        var items: [ShareLoadMissing] = []
        if signals.synthesizedTrip || signals.tripId.isEmpty { items.append(.tripId) }
        if signals.broker.isEmpty { items.append(.broker) }
        if signals.origin.isEmpty { items.append(.origin) }
        if signals.destination.isEmpty { items.append(.destination) }
        if signals.pickupDate == nil { items.append(.pickupDate) }
        if signals.deliveryDate == nil { items.append(.deliveryDate) }
        if signals.miles <= 0 { items.append(.miles) }
        return items
    }

    // MARK: - Pieces

    private static func labeledRate(_ text: String) -> Double {
        guard let raw = Rx.firstCapture(in: text, patterns: ratePatterns) else { return 0 }
        return NumberParsing.parseMoney(raw)
    }

    private static func broker(in text: String) -> String {
        if let name = Rx(#"(?m)^\s*Broker(?:\s*Name)?\s*[:\-]\s*(.+)$"#).firstMatch(in: text)?.group(1) {
            let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, cleaned.count <= 80 { return cleaned }
        }
        if let mc = Rx(#"\bMC\s*#?\s*[:\-]?\s*(\d{4,8})\b"#).firstMatch(in: text)?.group(1) {
            return "MC \(mc)"
        }
        return ""
    }

    private static let rejectedTripWords: Set<String> = [
        "RATE", "LOAD", "CONFIRMATION", "PICKUP", "DELIVERY", "TOTAL", "MILES",
        "DATE", "BROKER", "SHIPPER", "CONSIGNEE", "CARRIER", "DISPATCH", "PAY",
        "ORIGIN", "DESTINATION", "FROM", "NUMBER", "TRIP", "ADDRESS",
    ]

    private static func tripId(in text: String) -> String {
        guard let raw = Rx.firstCapture(in: text, patterns: tripPatterns) else { return "" }
        return cleanedTrip(raw) ?? ""
    }

    /// Drops ids the flexible parser invents from the word after "Confirmation", such as `RATE`.
    private static func cleanedTrip(_ raw: String) -> String? {
        let upper = TripID.normalize(raw)
        guard upper.count >= 4, !isGeneratedTrip(upper), !rejectedTripWords.contains(upper) else { return nil }
        if upper.range(of: #"^\d{1,2}[-/]\d{1,2}"#, options: .regularExpression) != nil { return nil }
        return upper
    }

    private static func isGeneratedTrip(_ id: String) -> Bool {
        TripID.normalize(id).range(of: #"^T-\d{9,}$"#, options: .regularExpression) != nil
    }

    private static func labeledPlace(_ text: String, labels: [String]) -> String? {
        let lines = text.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard !lower.contains("date") else { continue }
            guard labels.contains(where: { lower.contains($0) }) else { continue }
            if line.contains(":"), let value = line.split(separator: ":", maxSplits: 1).last {
                let candidate = String(value).trimmingCharacters(in: .whitespaces)
                if plausible(candidate) { return candidate }
                continue
            }
            for offset in 1...3 {
                let nextIndex = index + offset
                guard nextIndex < lines.count else { break }
                let candidate = lines[nextIndex].trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty { continue }
                if plausible(candidate) { return candidate }
            }
        }
        return nil
    }

    private static func allPlaces(_ text: String) -> [String] {
        var found: [String] = []
        for match in cityState.matches(in: text) {
            guard let city = match.group(1), let state = match.group(2), knownState(state) else { continue }
            let zip = match.group(3) ?? ""
            let place = zip.isEmpty
                ? "\(city.trimmingCharacters(in: .whitespaces)), \(state.uppercased())"
                : "\(city.trimmingCharacters(in: .whitespaces)), \(state.uppercased()) \(zip)"
            if !found.contains(where: { samePlace($0, place) }) {
                found.append(place)
            }
        }
        return found
    }

    private static func plausible(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return false }
        let parts = AddressParser.parseLine(trimmed)
        if knownState(parts.state) || parts.zip.count >= 5 { return true }
        return cityState.firstMatch(in: trimmed).flatMap { match in
            match.group(2).map(knownState)
        } ?? false
    }

    private static func knownState(_ raw: String) -> Bool {
        let code = USStates.normalize(raw)
        return USStates.isKnown(code) || canadian.contains(code)
    }

    private static func samePlace(_ lhs: String, _ rhs: String) -> Bool {
        lhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            == rhs.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func dates(in text: String, reference: Date) -> (pickup: Date?, delivery: Date?) {
        let year = Calendar(identifier: .gregorian).component(.year, from: reference)
        let pickupRaw = Rx(#"(?m)Pick\s*-?\s*up\s*Date\s*[:\-]?\s*([^\n]+)"#).firstMatch(in: text)?.group(1)
            ?? Rx(#"(?m)PU\s*Date\s*[:\-]?\s*([^\n]+)"#).firstMatch(in: text)?.group(1)
        let deliveryRaw = Rx(#"(?m)Deliver(?:y|ies)\s*Date\s*[:\-]?\s*([^\n]+)"#).firstMatch(in: text)?.group(1)
            ?? Rx(#"(?m)DEL\s*Date\s*[:\-]?\s*([^\n]+)"#).firstMatch(in: text)?.group(1)
        var pickup = pickupRaw.flatMap { date(from: $0, defaultYear: year) }
        var delivery = deliveryRaw.flatMap { date(from: $0, defaultYear: year) }
        if pickup == nil || delivery == nil {
            let generic = genericDates(in: text, defaultYear: year)
            if pickup == nil { pickup = generic.first }
            if delivery == nil {
                delivery = generic.first { candidate in
                    guard let pickup else { return true }
                    return candidate != pickup
                }
            }
        }
        return (pickup, delivery)
    }

    private static func genericDates(in text: String, defaultYear: Int) -> [Date] {
        let pattern = Rx(#"\b(\d{1,2}[./-]\d{1,2}[./-]\d{2,4}|\d{4}-\d{2}-\d{2}|(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{4})\b"#)
        var found: [Date] = []
        for match in pattern.matches(in: text) {
            guard let raw = match.group(1), let date = date(from: raw, defaultYear: defaultYear) else { continue }
            if !found.contains(date) { found.append(date) }
        }
        return found
    }

    private static func date(from raw: String, defaultYear: Int) -> Date? {
        let iso = ReceiptDateParser.normalize(raw, defaultYear: defaultYear)
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    /// Stable id when the sheet did not print a load number. Same text shares the same id.
    private static func fnv(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
