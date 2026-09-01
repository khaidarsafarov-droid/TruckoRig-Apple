import Foundation

/// Address text split into the pieces the journal needs.
public struct AddressParts: Equatable, Sendable {
    public var facility: String?
    public var fullAddress: String
    public var city: String
    public var state: String
    public var zip: String

    public init(facility: String? = nil, fullAddress: String = "", city: String = "", state: String = "", zip: String = "") {
        self.facility = facility
        self.fullAddress = fullAddress
        self.city = city
        self.state = state
        self.zip = zip
    }

    public static let empty = AddressParts()
}

/// Splits Relay addresses into facility / city / state / zip.
///
/// Relay prints stops in several shapes: one-liners (`SWF2, Garner, NC`), slash-delimited
/// (`SWF2 / 100 Main St / Garner, NC 27529`) and multi-line blocks.
public enum AddressParser {

    private static let facilityCityState = Rx(
        #"^([A-Za-z0-9][A-Za-z0-9\-]{0,23}),\s*(.+),\s*([A-Za-z]{2}|[A-Za-z][A-Za-z .]+[A-Za-z])\s*(\d{5}(?:-\d{4})?)?\s*$"#,
        options: []
    )
    private static let cityStateZip = Rx(#"^(.+),\s*([A-Za-z]{2})\s+(\d{5}(?:-\d{4})?)\s*$"#, options: [])
    private static let cityState = Rx(#"^(.+),\s*([A-Za-z]{2})\s*$"#, options: [])
    private static let cityFullStateZip = Rx(#"^(.+),\s*([A-Za-z][A-Za-z .]+[A-Za-z])\s*(\d{5}(?:-\d{4})?)?\s*$"#, options: [])

    public static func parseLine(_ raw: String) -> AddressParts {
        let line = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
        guard !line.isEmpty else { return .empty }

        let slashParts = line.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if slashParts.count >= 2 {
            let facility = slashParts[0].count <= 24 ? slashParts[0] : nil
            let street = slashParts.count > 1 ? slashParts[1] : ""
            let tail = slashParts.dropFirst(2).joined(separator: ", ")
            let cityStateZipText = tail.isEmpty ? (slashParts.last ?? "") : tail
            let split = splitCityStateZip(cityStateZipText)
            let full = [facility, street.isEmpty ? nil : street, cityStateZipText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return AddressParts(facility: facility, fullAddress: full, city: split.city, state: split.state, zip: split.zip)
        }

        if let relay = parseFacilityCityState(line) { return relay }

        let split = splitCityStateZip(line)
        return AddressParts(facility: nil, fullAddress: line, city: split.city, state: split.state, zip: split.zip)
    }

    /// Multi-line Relay block: facility line, optional street lines, then `City, ST ZIP`.
    public static func parseLines(_ lines: [String]) -> AddressParts {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return .empty }
        if cleaned.count == 1 { return parseLine(cleaned[0]) }

        let cityStateIndex = cleaned.lastIndex { line in
            let split = splitCityStateZip(line)
            return !split.state.isEmpty || !split.zip.isEmpty
        }

        let split = cityStateIndex.map { splitCityStateZip(cleaned[$0]) } ?? (city: "", state: "", zip: "")
        let facilityCandidate = cleaned.first
        let streetLines: [String]
        switch cityStateIndex {
        case let index? where index > 1: streetLines = Array(cleaned[1..<index])
        case 1: streetLines = []
        default: streetLines = Array(cleaned.dropFirst())
        }

        let street = streetLines.joined(separator: ", ")
        let cityStateLine = cityStateIndex.map { cleaned[$0] }
        let full = [facilityCandidate, street.isEmpty ? nil : street, cityStateLine]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        let facilityIsSeparateLine = (cityStateIndex ?? 0) > 0
        let facility = facilityCandidate.flatMap { candidate -> String? in
            guard facilityIsSeparateLine, candidate.count <= 24, !candidate.contains(",") else { return nil }
            return candidate
        }

        return AddressParts(
            facility: facility,
            fullAddress: full.isEmpty ? cleaned.joined(separator: ", ") : full,
            city: split.city,
            state: split.state,
            zip: split.zip
        )
    }

    /// `FACILITY, City, ST[ ZIP]`. Requires two commas so a plain `City, ST` stays a city/state pair.
    private static func parseFacilityCityState(_ line: String) -> AddressParts? {
        guard let match = facilityCityState.firstMatch(in: line) else { return nil }
        let facility = match.groupOrEmpty(1)
        let city = match.groupOrEmpty(2)
        let stateRaw = match.groupOrEmpty(3)
        let state = USStates.normalize(stateRaw)
        guard !city.isEmpty, !state.isEmpty, !facility.contains(" ") else { return nil }
        guard state.count == 2 || USStates.isKnown(stateRaw) else { return nil }
        return AddressParts(
            facility: facility,
            fullAddress: line,
            city: city,
            state: state,
            zip: match.group(4) ?? ""
        )
    }

    static func splitCityStateZip(_ part: String) -> (city: String, state: String, zip: String) {
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "", "") }

        // Prefer a trailing two-letter state so "SWF2, Garner, NC" does not read Garner as the state.
        if let match = cityStateZip.firstMatch(in: trimmed) {
            return (cityFromLeft(match.groupOrEmpty(1)), match.groupOrEmpty(2).uppercased(), match.groupOrEmpty(3))
        }
        if let match = cityState.firstMatch(in: trimmed) {
            return (cityFromLeft(match.groupOrEmpty(1)), match.groupOrEmpty(2).uppercased(), "")
        }
        if let match = cityFullStateZip.firstMatch(in: trimmed) {
            let stateRaw = match.groupOrEmpty(2)
            if USStates.isKnown(stateRaw) {
                return (cityFromLeft(match.groupOrEmpty(1)), USStates.normalize(stateRaw), match.group(3) ?? "")
            }
        }
        return (trimmed, "", "")
    }

    /// Keeps only the last comma-separated component, dropping facility/street prefixes.
    private static func cityFromLeft(_ left: String) -> String {
        let trimmed = left.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.split(separator: ",").last else { return trimmed }
        let city = last.trimmingCharacters(in: .whitespaces)
        return city.isEmpty ? trimmed : city
    }
}
