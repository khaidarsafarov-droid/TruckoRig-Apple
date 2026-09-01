import Foundation

/// Regex/state-machine parser for Amazon Relay trip messages.
///
/// Handles a single pasted trip, several trips in one paste, and whole exported chat histories.
/// A trip block only becomes a `ParsedLoad` when it has a Trip ID, a positive Total Rate and at
/// least one usable pickup or delivery address.
public enum LoadMessageParser {

    static let tripIdPatterns = [
        Rx(#"Trip\s*ID\s*[:|]?\s*(T-[A-Z0-9]+)"#),
        Rx(#"Trip\s*ID\s*[:|]?\s*([A-Z0-9\-]+)"#),
        Rx(#"\b(T-[A-Z0-9]{6,})\b"#),
    ]
    static let totalRatePattern = Rx(#"Total\s*Rate\s*[:\s]*\$?\s*([\d.,]+)"#)
    static let totalMilesPattern = Rx(#"Total\s*Loaded\s*Miles\s*[:\s]*([\d.,]+)"#)
    static let inlineRatePattern = Rx(#"Rate\s+\$?([\d.,]+)"#)
    static let inlineMilesPattern = Rx(#"([\d.,]+)\s*mi\b"#)
    static let tripBlockSplitPattern = Rx(#"^Trip\s*ID"#, options: [.caseInsensitive, .anchorsMatchLines])

    /// Parses every trip in `rawMessage`.
    ///
    /// - Parameter reference: When the message was written. Relay omits years, so this anchors
    ///   `MM/DD` schedules. Chat-history headers inside the text override it per block.
    public static func parseAll(
        _ rawMessage: String,
        reference: Date = Date(),
        timeZone: TimeZone = .current
    ) -> [ParsedLoad] {
        let normalized = StyledTextNormalizer.normalize(
            rawMessage.replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard MessageClassifier.isLoadLike(normalized) else { return [] }

        let history = ChatHistoryDates(text: normalized, timeZone: timeZone)
        let times = RelayTimeParser(timeZone: timeZone)

        return splitTripBlocks(normalized).compactMap { block in
            let blockReference = history.reference(at: block.offset, fallback: reference)
            return parseBlock(block.text, rawMessage: rawMessage, reference: blockReference, times: times)
        }
    }

    public static func parseOne(
        _ rawMessage: String,
        reference: Date = Date(),
        timeZone: TimeZone = .current
    ) -> ParsedLoad? {
        parseAll(rawMessage, reference: reference, timeZone: timeZone).first
    }

    // MARK: - Block splitting

    struct TripBlock {
        let offset: Int
        let text: String
    }

    static func splitTripBlocks(_ text: String) -> [TripBlock] {
        let matches = tripBlockSplitPattern.matches(in: text)
        guard !matches.isEmpty else { return [TripBlock(offset: 0, text: text)] }

        var blocks: [TripBlock] = []
        for (index, match) in matches.enumerated() {
            let start = match.range.lowerBound
            let end = index + 1 < matches.count ? matches[index + 1].range.lowerBound : text.endIndex
            let body = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty, MessageClassifier.isLoadLike(body) else { continue }
            blocks.append(TripBlock(offset: text.distance(from: text.startIndex, to: start), text: body))
        }
        return blocks.isEmpty ? [TripBlock(offset: 0, text: text)] : blocks
    }

    // MARK: - Single trip

    static func parseBlock(
        _ block: String,
        rawMessage: String,
        reference: Date,
        times: RelayTimeParser
    ) -> ParsedLoad? {
        guard let tripId = Rx.firstCapture(in: block, patterns: tripIdPatterns)?.uppercased() else { return nil }

        let totalRate = parseRate(in: block)
        let totalMiles = NumberParsing.sanitizeLoadedMiles(parseMiles(in: block), totalRate: totalRate)
        let stops = parseStops(in: block, reference: reference, times: times)

        let parsed = ParsedLoad(
            tripId: tripId,
            totalRate: totalRate,
            totalMiles: totalMiles,
            date: loadDate(for: stops, times: times, reference: reference),
            stops: stops,
            rawMessage: rawMessage
        )

        // A trip without money or without a single resolvable address is not a load — importing it
        // would create an empty row the driver has to clean up by hand.
        guard parsed.totalRate > 0, !parsed.pointA.isEmpty || !parsed.pointB.isEmpty else { return nil }
        return parsed
    }

    private static func parseRate(in block: String) -> Double {
        if let value = totalRatePattern.firstMatch(in: block)?.group(1) {
            return NumberParsing.parseMoney(value)
        }
        if let value = inlineRatePattern.firstMatch(in: block)?.group(1) {
            return NumberParsing.parseMoney(value)
        }
        return 0
    }

    private static func parseMiles(in block: String) -> Double {
        if let value = totalMilesPattern.firstMatch(in: block)?.group(1) {
            return NumberParsing.parseMiles(value)
        }
        // Fall back to the largest "X mi" in the block: the first one is usually a single leg
        // rather than Total Loaded Miles.
        let candidates = inlineMilesPattern.matches(in: block)
            .compactMap { $0.group(1) }
            .map(NumberParsing.parseMiles)
            .filter { $0 > 0 }
        return candidates.max() ?? 0
    }

    /// Load date: the day of the first pickup, falling back to the last delivery.
    ///
    /// Anchored at local noon so week attribution never flips across a timezone change.
    private static func loadDate(for stops: [StopDraft], times: RelayTimeParser, reference: Date) -> Date? {
        let pickups = stops.filter { $0.type == .pickup }
        let deliveries = stops.filter { $0.type == .delivery }
        let day = pickups.compactMap(\.localDay).min() ?? deliveries.compactMap(\.localDay).min()
        guard let day else { return nil }
        return times.noon(onLocalDay: day)
    }
}
