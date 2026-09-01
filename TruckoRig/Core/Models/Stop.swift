import Foundation
import SwiftData

/// One pickup or delivery appointment on a load.
@Model
final class Stop {
    @Attribute(.unique) var id: UUID
    var type: StopType
    var stopNumber: Int
    /// Relay `PU#` code of the leg this stop belongs to.
    var puNumber: String?
    var note: String?
    var facility: String?
    var fullAddress: String
    var city: String
    var state: String
    var zip: String?
    /// Appointment instant, resolved using the printed timezone when Relay supplied one.
    var scheduledTime: Date?
    /// Schedule text exactly as Relay printed it, kept for auditing a parse.
    var scheduledTimeRaw: String?
    /// Timezone abbreviation, e.g. `EDT`.
    var timezone: String?

    var load: Load?

    init(
        id: UUID = UUID(),
        type: StopType,
        stopNumber: Int = 0,
        puNumber: String? = nil,
        note: String? = nil,
        facility: String? = nil,
        fullAddress: String = "",
        city: String = "",
        state: String = "",
        zip: String? = nil,
        scheduledTime: Date? = nil,
        scheduledTimeRaw: String? = nil,
        timezone: String? = nil
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
        self.scheduledTime = scheduledTime
        self.scheduledTimeRaw = scheduledTimeRaw
        self.timezone = timezone
    }

    convenience init(draft: StopDraft) {
        self.init(
            type: draft.type,
            stopNumber: draft.stopNumber,
            puNumber: draft.puNumber,
            note: draft.note,
            facility: draft.facility,
            fullAddress: draft.fullAddress,
            city: draft.city,
            state: draft.state,
            zip: draft.zip.isEmpty ? nil : draft.zip,
            scheduledTime: draft.scheduledTime,
            scheduledTimeRaw: draft.scheduledTimeRaw.isEmpty ? nil : draft.scheduledTimeRaw,
            timezone: draft.timezone.isEmpty ? nil : draft.timezone
        )
    }

    var cityState: String {
        let parts = [city, state].filter { !$0.isEmpty }
        return parts.isEmpty ? fullAddress : parts.joined(separator: ", ")
    }

    var draft: StopDraft {
        StopDraft(
            type: type,
            stopNumber: stopNumber,
            puNumber: puNumber,
            note: note,
            facility: facility,
            fullAddress: fullAddress,
            city: city,
            state: state,
            zip: zip ?? "",
            scheduledTimeRaw: scheduledTimeRaw ?? "",
            scheduledTime: scheduledTime,
            timezone: timezone ?? ""
        )
    }
}
