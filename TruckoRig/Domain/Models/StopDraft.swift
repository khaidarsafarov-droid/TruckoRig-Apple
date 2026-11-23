import Foundation

/// One parsed or hand-edited stop, before it becomes a SwiftData `Stop`.
public struct StopDraft: Equatable, Hashable, Sendable, Identifiable {
    /// Stable row identity for the editor. Two stops with the same text stay distinct rows.
    /// Equality ignores it so a parsed stop still matches a hand-built one.
    public var id: UUID
    public var type: StopType
    public var stopNumber: Int
    /// Relay `PU#` code of the leg this stop belongs to.
    public var puNumber: String?
    public var note: String?
    /// Relay warehouse code, e.g. `SWF2`.
    public var facility: String?
    public var fullAddress: String
    public var city: String
    public var state: String
    public var zip: String
    /// Original schedule text as printed by Relay, e.g. `07/06 08:00 EDT`.
    public var scheduledTimeRaw: String
    /// `scheduledTimeRaw` resolved to an instant, honouring the printed timezone when known.
    public var scheduledTime: Date?
    /// Calendar day exactly as printed (`YYYY-MM-DD`), independent of the device timezone.
    ///
    /// Week attribution uses this so a driver crossing timezones never sees a load jump days.
    public var localDay: String?
    /// Timezone abbreviation trailing the schedule text, e.g. `EDT`.
    public var timezone: String

    public init(
        type: StopType,
        stopNumber: Int = 0,
        puNumber: String? = nil,
        note: String? = nil,
        facility: String? = nil,
        fullAddress: String = "",
        city: String = "",
        state: String = "",
        zip: String = "",
        scheduledTimeRaw: String = "",
        scheduledTime: Date? = nil,
        localDay: String? = nil,
        timezone: String = "",
        id: UUID = UUID()
    ) {
        self.id = id
        self.type = type
        self.stopNumber = stopNumber
        self.puNumber = puNumber
        self.note = note
        self.facility = facility
        self.fullAddress = fullAddress
        self.city = city
        self.state = state
        self.zip = zip
        self.scheduledTimeRaw = scheduledTimeRaw
        self.scheduledTime = scheduledTime
        self.localDay = localDay
        self.timezone = timezone
    }

    /// `"City, ST"`, falling back to the full address when the split failed.
    public var cityState: String {
        let parts = [city, state].filter { !$0.isEmpty }
        return parts.isEmpty ? fullAddress : parts.joined(separator: ", ")
    }

    public static func == (lhs: StopDraft, rhs: StopDraft) -> Bool {
        lhs.type == rhs.type
            && lhs.stopNumber == rhs.stopNumber
            && lhs.puNumber == rhs.puNumber
            && lhs.note == rhs.note
            && lhs.facility == rhs.facility
            && lhs.fullAddress == rhs.fullAddress
            && lhs.city == rhs.city
            && lhs.state == rhs.state
            && lhs.zip == rhs.zip
            && lhs.scheduledTimeRaw == rhs.scheduledTimeRaw
            && lhs.scheduledTime == rhs.scheduledTime
            && lhs.localDay == rhs.localDay
            && lhs.timezone == rhs.timezone
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(stopNumber)
        hasher.combine(puNumber)
        hasher.combine(note)
        hasher.combine(facility)
        hasher.combine(fullAddress)
        hasher.combine(city)
        hasher.combine(state)
        hasher.combine(zip)
        hasher.combine(scheduledTimeRaw)
        hasher.combine(scheduledTime)
        hasher.combine(localDay)
        hasher.combine(timezone)
    }
}
