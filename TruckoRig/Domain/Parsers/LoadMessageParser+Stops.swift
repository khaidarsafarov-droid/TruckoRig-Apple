import Foundation

/// Stop extraction. Relay text arrives in three shapes and each gets its own pass, tried in order
/// of specificity: multi-leg `PU#` blocks, `Pu-address:` / `Del-address:` label pairs, and the
/// older pipe-delimited rows.
extension LoadMessageParser {

    static let puHeaderPattern = Rx(#"PU#\s*(\S+)"#)
    static let sectionPattern = Rx(#"^(Pu|Del)-(address|time)\s*[:\s]*(.*)$"#)
    static let puPipePattern = Rx(#"PU\s+([A-Z0-9\-]+)\s*\|\s*(.+?)\s*\|\s*([^\n|]+)\s*\|\s*(?:Note:\s*)?([^\n]*)"#)
    static let delPipePattern = Rx(#"DEL\s*\|\s*([^,\n|]+)\s*,\s*([^\n|]+)\s*\|\s*([^\n|]+)"#)

    static func parseStops(in block: String, reference: Date, times: RelayTimeParser) -> [StopDraft] {
        let legs = parseLegStops(in: block, reference: reference, times: times)
        if !legs.isEmpty { return legs }

        let pairs = parseLabelPairStops(in: block, reference: reference, times: times)
        if !pairs.isEmpty { return pairs }

        return parsePipeStops(in: block, reference: reference, times: times)
    }

    // MARK: - Multi-leg PU# blocks

    private static func parseLegStops(in block: String, reference: Date, times: RelayTimeParser) -> [StopDraft] {
        let headers = puHeaderPattern.matches(in: block)
        guard !headers.isEmpty else { return [] }

        var stops: [StopDraft] = []
        for (index, header) in headers.enumerated() {
            let start = header.range.lowerBound
            let end = index + 1 < headers.count ? headers[index + 1].range.lowerBound : block.endIndex
            let segment = String(block[start..<end])
            let puCode = header.group(1)
            let sections = parseSections(in: segment)

            if let addressLines = sections["pu-address"] {
                stops.append(makeStop(
                    type: .pickup,
                    stopNumber: stops.count + 1,
                    puNumber: puCode,
                    note: sections["note"]?.first,
                    addressLines: addressLines,
                    scheduleText: sections["pu-time"]?.first ?? "",
                    reference: reference,
                    times: times
                ))
            }
            if let addressLines = sections["del-address"] {
                stops.append(makeStop(
                    type: .delivery,
                    stopNumber: stops.count + 1,
                    puNumber: nil,
                    note: nil,
                    addressLines: addressLines,
                    scheduleText: sections["del-time"]?.first ?? "",
                    reference: reference,
                    times: times
                ))
            }
        }
        return stops
    }

    /// Groups a leg's lines under `pu-address`, `pu-time`, `del-address`, `del-time` and `note`.
    private static func parseSections(in segment: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var currentKey: String?

        for rawLine in segment.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.lowercased().hasPrefix("pu#") { continue }

            if let match = sectionPattern.firstMatch(in: line) {
                let kind = match.groupOrEmpty(1).lowercased()
                let field = match.groupOrEmpty(2).lowercased()
                let key = "\(kind)-\(field)"
                currentKey = key
                var values = result[key] ?? []
                if let remainder = match.group(3) { values.append(remainder) }
                result[key] = values
                continue
            }

            if line.lowercased().hasPrefix("note") {
                currentKey = "note"
                var values = result["note"] ?? []
                if let text = noteText(from: line) { values.append(text) }
                result["note"] = values
                continue
            }

            if let key = currentKey, !isTripLevelLine(line) {
                result[key, default: []].append(line)
            }
        }
        return result
    }

    // MARK: - Pu-address / Del-address label pairs

    private static func parseLabelPairStops(in block: String, reference: Date, times: RelayTimeParser) -> [StopDraft] {
        struct Pending {
            var type: StopType
            var lines: [String]
            var scheduleText: String
            var note: String?
        }

        var pending: [Pending] = []
        var current: Pending?
        var lastPickupTime = ""
        var lastDeliveryTime = ""
        var lastNote: String?

        func flush() {
            if let active = current, !active.lines.isEmpty { pending.append(active) }
            current = nil
        }

        for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.lowercased().hasPrefix("pu#") { continue }

            if let match = sectionPattern.firstMatch(in: line) {
                let isPickup = match.groupOrEmpty(1).lowercased() == "pu"
                let field = match.groupOrEmpty(2).lowercased()
                let remainder = match.group(3) ?? ""

                if field == "time" {
                    if isPickup { lastPickupTime = remainder } else { lastDeliveryTime = remainder }
                } else {
                    flush()
                    current = Pending(
                        type: isPickup ? .pickup : .delivery,
                        lines: remainder.isEmpty ? [] : [remainder],
                        scheduleText: isPickup ? lastPickupTime : lastDeliveryTime,
                        note: isPickup ? lastNote : nil
                    )
                }
                continue
            }

            if line.lowercased().hasPrefix("note") {
                lastNote = noteText(from: line)
                continue
            }

            if current != nil, !isTripLevelLine(line) {
                current?.lines.append(line)
            }
        }
        flush()

        return pending.enumerated().map { index, item in
            makeStop(
                type: item.type,
                stopNumber: index + 1,
                puNumber: nil,
                note: item.note,
                addressLines: item.lines,
                scheduleText: item.scheduleText,
                reference: reference,
                times: times
            )
        }
    }

    // MARK: - Legacy pipe rows

    private static func parsePipeStops(in block: String, reference: Date, times: RelayTimeParser) -> [StopDraft] {
        var stops: [StopDraft] = []

        for match in puPipePattern.matches(in: block) {
            let address = "\(match.groupOrEmpty(2)), \(match.groupOrEmpty(3))"
            stops.append(makeStop(
                type: .pickup,
                stopNumber: stops.count + 1,
                puNumber: match.group(1),
                note: match.group(4),
                addressLines: [address],
                scheduleText: match.groupOrEmpty(3),
                reference: reference,
                times: times
            ))
        }

        for match in delPipePattern.matches(in: block) {
            var stop = makeStop(
                type: .delivery,
                stopNumber: stops.count + 1,
                puNumber: nil,
                note: nil,
                addressLines: [match.groupOrEmpty(2)],
                scheduleText: match.groupOrEmpty(3),
                reference: reference,
                times: times
            )
            stop.facility = match.group(1)
            stops.append(stop)
        }

        return stops
    }

    // MARK: - Helpers

    private static func makeStop(
        type: StopType,
        stopNumber: Int,
        puNumber: String?,
        note: String?,
        addressLines: [String],
        scheduleText: String,
        reference: Date,
        times: RelayTimeParser
    ) -> StopDraft {
        let address = AddressParser.parseLines(addressLines)
        let schedule = times.resolve(scheduleText, reference: reference)
        return StopDraft(
            type: type,
            stopNumber: stopNumber,
            puNumber: puNumber,
            note: note,
            facility: address.facility,
            fullAddress: address.fullAddress,
            city: address.city,
            state: address.state,
            zip: address.zip,
            scheduledTimeRaw: scheduleText,
            scheduledTime: schedule?.date,
            localDay: schedule?.localDay,
            timezone: schedule?.timezoneAbbreviation ?? times.timezoneAbbreviation(in: scheduleText)
        )
    }

    private static func isTripLevelLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.hasPrefix("trip") || lowered.hasPrefix("total") || lowered.hasPrefix("pu#")
    }

    private static func noteText(from line: String) -> String? {
        let afterLabel: String
        if let colon = line.firstIndex(of: ":") {
            afterLabel = String(line[line.index(after: colon)...])
        } else {
            afterLabel = String(line.dropFirst("Note".count))
        }
        let trimmed = afterLabel.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
