import Foundation

/// A stop schedule resolved from Relay text.
public struct ResolvedSchedule: Equatable, Sendable {
    /// Instant of the appointment, using the printed timezone when it is recognised.
    public var date: Date
    /// Calendar day exactly as printed, `YYYY-MM-DD`.
    public var localDay: String
    /// Timezone abbreviation that was printed, e.g. `EDT`. Empty when absent.
    public var timezoneAbbreviation: String

    public init(date: Date, localDay: String, timezoneAbbreviation: String) {
        self.date = date
        self.localDay = localDay
        self.timezoneAbbreviation = timezoneAbbreviation
    }
}

/// Parses Relay stop schedules (`07/06 08:00 EDT`), ISO (`2025-07-06 08:00`) and EU
/// (`06.07.2025 08:00`) timestamps.
///
/// Relay omits the year, so the year is inferred from the message's own reference date rather than
/// the wall clock — otherwise a August 2025 history import gets filed under August 2026.
public struct RelayTimeParser: Sendable {

    private let deviceTimeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        self.deviceTimeZone = timeZone
    }

    private static let isoPattern = Rx(#"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{1,2}):(\d{2}))?"#, options: [])
    private static let euPattern = Rx(#"^(\d{1,2})\.(\d{1,2})\.(\d{2,4})(?:\s+(\d{1,2}):(\d{2}))?"#, options: [])
    private static let relayPattern = Rx(#"^(\d{1,2})/(\d{1,2})(?:\s+(\d{1,2}):(\d{2}))?(?:\s+([A-Z]{2,4}))?\s*$"#, options: [])
    private static let trailingZonePattern = Rx(#"\b([A-Z]{2,4})\s*$"#, options: [])

    /// Fixed offsets for North American zone abbreviations Relay prints.
    ///
    /// Named zones would be ambiguous (`CST` is also China Standard Time), and the printed
    /// abbreviation already encodes whether daylight time was in effect.
    private static let zoneOffsets: [String: Int] = [
        "AST": -4, "ADT": -3,
        "EST": -5, "EDT": -4, "ET": -5,
        "CST": -6, "CDT": -5, "CT": -6,
        "MST": -7, "MDT": -6, "MT": -7,
        "PST": -8, "PDT": -7, "PT": -8,
        "AKST": -9, "AKDT": -8,
        "HST": -10, "HAST": -10, "HADT": -9,
        "UTC": 0, "GMT": 0,
    ]

    public func timeZone(forAbbreviation abbreviation: String) -> TimeZone? {
        guard let hours = Self.zoneOffsets[abbreviation.uppercased()] else { return nil }
        return TimeZone(secondsFromGMT: hours * 3600)
    }

    /// Extracts the trailing timezone abbreviation, e.g. `EDT` from `07/06 08:00 EDT`.
    public func timezoneAbbreviation(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = Self.trailingZonePattern.firstMatch(in: trimmed) else { return "" }
        return match.groupOrEmpty(1)
    }

    /// Resolves one schedule string.
    ///
    /// - Parameters:
    ///   - yearHint: Year already known for this load (from `Load.date`).
    ///   - trustYearHint: Keep `yearHint` verbatim instead of re-running the inference. Used when
    ///     re-hydrating a stored load, so a saved date never drifts on a later read.
    ///   - reference: Instant the message was written or pasted.
    public func resolve(
        _ text: String,
        yearHint: Int? = nil,
        trustYearHint: Bool = false,
        reference: Date = Date()
    ) -> ResolvedSchedule? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = Self.isoPattern.firstMatch(in: trimmed) {
            return build(
                year: Int(match.groupOrEmpty(1)) ?? 0,
                month: Int(match.groupOrEmpty(2)) ?? 0,
                day: Int(match.groupOrEmpty(3)) ?? 0,
                hour: Int(match.group(4) ?? "0") ?? 0,
                minute: Int(match.group(5) ?? "0") ?? 0,
                abbreviation: timezoneAbbreviation(in: trimmed)
            )
        }

        if let match = Self.euPattern.firstMatch(in: trimmed) {
            var year = Int(match.groupOrEmpty(3)) ?? 0
            if year < 100 { year += 2000 }
            return build(
                year: year,
                month: Int(match.groupOrEmpty(2)) ?? 0,
                day: Int(match.groupOrEmpty(1)) ?? 0,
                hour: Int(match.group(4) ?? "0") ?? 0,
                minute: Int(match.group(5) ?? "0") ?? 0,
                abbreviation: timezoneAbbreviation(in: trimmed)
            )
        }

        if let match = Self.relayPattern.firstMatch(in: trimmed) {
            let month = Int(match.groupOrEmpty(1)) ?? 0
            let day = Int(match.groupOrEmpty(2)) ?? 0
            let year = resolveYear(
                month: month,
                day: day,
                yearHint: yearHint,
                trustYearHint: trustYearHint,
                reference: reference
            )
            return build(
                year: year,
                month: month,
                day: day,
                hour: Int(match.group(3) ?? "0") ?? 0,
                minute: Int(match.group(4) ?? "0") ?? 0,
                abbreviation: match.group(5) ?? ""
            )
        }

        return nil
    }

    private func build(year: Int, month: Int, day: Int, hour: Int, minute: Int, abbreviation: String) -> ResolvedSchedule? {
        guard (1...12).contains(month), (1...31).contains(day), (1970...2100).contains(year) else { return nil }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        let zone = timeZone(forAbbreviation: abbreviation) ?? deviceTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else { return nil }

        return ResolvedSchedule(
            date: date,
            localDay: String(format: "%04d-%02d-%02d", year, month, day),
            timezoneAbbreviation: abbreviation.uppercased()
        )
    }

    // MARK: - Year inference

    /// Year for a `MM/DD` schedule.
    ///
    /// A trusted hint wins outright; otherwise the year whose `MM/DD` lands closest to the
    /// message's own timestamp is chosen, which keeps December→January trips together.
    public func resolveYear(
        month: Int,
        day: Int,
        yearHint: Int?,
        trustYearHint: Bool,
        reference: Date
    ) -> Int {
        if trustYearHint, let yearHint { return yearHint }
        guard (1...12).contains(month), (1...31).contains(day) else {
            return yearHint ?? calendarYear(of: reference)
        }
        if let anchor = yearHint {
            return resolveYear(month: month, day: day, anchorYear: anchor, reference: reference)
        }
        return closestYear(month: month, day: day, centerYear: calendarYear(of: reference), reference: reference)
    }

    /// Year when an anchor is known (the message year or the stored load date).
    ///
    /// Bookings more than two weeks past the anchor are almost always last year's history rather
    /// than a genuine future appointment.
    public func resolveYear(month: Int, day: Int, anchorYear: Int, reference: Date) -> Int {
        guard (1...12).contains(month), (1...31).contains(day) else { return anchorYear }
        let bookingHorizon: TimeInterval = 14 * 86_400
        if let candidate = date(year: anchorYear, month: month, day: day),
           candidate.timeIntervalSince(reference) > bookingHorizon {
            return anchorYear - 1
        }
        return closestYear(month: month, day: day, centerYear: anchorYear, reference: reference)
    }

    private func closestYear(month: Int, day: Int, centerYear: Int, reference: Date) -> Int {
        let candidates = (centerYear - 1)...(centerYear + 1)
        return candidates.min { lhs, rhs in
            distance(year: lhs, month: month, day: day, from: reference)
                < distance(year: rhs, month: month, day: day, from: reference)
        } ?? centerYear
    }

    private func distance(year: Int, month: Int, day: Int, from reference: Date) -> TimeInterval {
        guard let candidate = date(year: year, month: month, day: day) else { return .greatestFiniteMagnitude }
        return abs(candidate.timeIntervalSince(reference))
    }

    private func date(year: Int, month: Int, day: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = deviceTimeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return calendar.date(from: components)
    }

    private func calendarYear(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = deviceTimeZone
        return calendar.component(.year, from: date)
    }

    /// Noon on `localDay` in the device timezone — a stable anchor for week attribution.
    public func noon(onLocalDay localDay: String) -> Date? {
        let parts = localDay.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = deviceTimeZone
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        return calendar.date(from: components)
    }
}
