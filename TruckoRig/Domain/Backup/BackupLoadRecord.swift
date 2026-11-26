import Foundation

/// Android `BackupSchema`.
public enum BackupSchema {
    public static let current = 2
    public static let v1 = 1
    public static let v2 = 2
    public static let jsonMIME = "application/json"
    /// Android `BrandConstants.FILE_PREFIX`.
    public static let filePrefix = "TruckoRig"

    public static func resolve(schemaVersion: Int, version: Int) -> Int {
        if schemaVersion > 0 { return schemaVersion }
        if version > 0 { return version }
        return v1
    }

    /// Android `BackupSchema.jsonFileName`: `<FILE_PREFIX>_Backup_yyyyMMdd_HHmmss.json`.
    public static func jsonFileName(exportedAt: Int64, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = Date(timeIntervalSince1970: Double(exportedAt) / 1000)
        let stamp = DateFormatCache.string(
            from: date,
            pattern: "yyyyMMdd_HHmmss",
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            timeZone: timeZone
        )
        return "\(filePrefix)_Backup_\(stamp).json"
    }
}

public struct BackupStop: Equatable, Sendable {
    public var id: Int
    public var loadId: String
    public var stopNumber: Int
    public var type: String
    public var puNumber: String?
    public var note: String?
    public var scheduledTime: String
    public var timezone: String
    public var facilityCode: String?
    public var fullAddress: String
    public var city: String
    public var state: String
    public var zip: String

    public init(
        id: Int = 0,
        loadId: String = "",
        stopNumber: Int = 0,
        type: String = "PU",
        puNumber: String? = nil,
        note: String? = nil,
        scheduledTime: String = "",
        timezone: String = "",
        facilityCode: String? = nil,
        fullAddress: String = "",
        city: String = "",
        state: String = "",
        zip: String = ""
    ) {
        self.id = id
        self.loadId = loadId
        self.stopNumber = stopNumber
        self.type = type
        self.puNumber = puNumber
        self.note = note
        self.scheduledTime = scheduledTime
        self.timezone = timezone
        self.facilityCode = facilityCode
        self.fullAddress = fullAddress
        self.city = city
        self.state = state
        self.zip = zip
    }
}

public struct BackupPenalty: Equatable, Sendable {
    public var id: Int
    public var loadId: String
    public var description: String
    /// Unboxed `Money` cents. Gson writes a JSON number, not `{"cents":…}`.
    public var amountCents: Int64

    public init(id: Int = 0, loadId: String = "", description: String = "", amountCents: Int64 = 0) {
        self.id = id
        self.loadId = loadId
        self.description = description
        self.amountCents = amountCents
    }
}

public struct BackupLoad: Equatable, Sendable {
    public var id: String
    public var tripId: String
    public var date: String
    public var totalRateCents: Int64
    public var totalMiles: Double
    public var pointA: String
    public var pointB: String
    public var puCount: Int
    public var delCount: Int
    public var weekNumber: Int
    public var year: Int
    public var rawMessage: String
    public var parsedAt: Int64
    public var updatedAt: Int64
    public var route: String
    public var firstPuCityState: String
    public var lastDelCityState: String
    public var durationDays: Double
    public var paceCents: Int64
    public var stopCount: Int
    public var isDispute: Bool
    public var disputeResponseDate: String?
    public var disputeCompleted: Bool
    public var disputeAmountCents: Int64?
    public var disputeApplyToLoad: Bool
    public var disputeAmountApplied: Bool
    public var actualFinishDate: String?
    public var stops: [BackupStop]
    public var penalties: [BackupPenalty]
    public var equipmentType: String?
    public var deadheadMiles: Double
    /// Android `Load.isCancelled`. Older files have no key and read as active.
    public var isCancelled: Bool
    /// Android `Load.cancelledAt`, epoch millis.
    public var cancelledAt: Int64?
    /// Android `Load.originalRate`: nullable `Money`, so Gson boxes it as `{"cents":…}`.
    public var originalRateCents: Int64?
    public var originalMiles: Double?

    public init(
        id: String = "",
        tripId: String = "",
        date: String = "",
        totalRateCents: Int64 = 0,
        totalMiles: Double = 0,
        pointA: String = "",
        pointB: String = "",
        puCount: Int = 0,
        delCount: Int = 0,
        weekNumber: Int = 0,
        year: Int = 0,
        rawMessage: String = "",
        parsedAt: Int64 = 0,
        updatedAt: Int64 = 0,
        route: String = "",
        firstPuCityState: String = "",
        lastDelCityState: String = "",
        durationDays: Double = 0,
        paceCents: Int64 = 0,
        stopCount: Int = 0,
        isDispute: Bool = false,
        disputeResponseDate: String? = nil,
        disputeCompleted: Bool = false,
        disputeAmountCents: Int64? = nil,
        disputeApplyToLoad: Bool = false,
        disputeAmountApplied: Bool = false,
        actualFinishDate: String? = nil,
        stops: [BackupStop] = [],
        penalties: [BackupPenalty] = [],
        equipmentType: String? = nil,
        deadheadMiles: Double = 0,
        isCancelled: Bool = false,
        cancelledAt: Int64? = nil,
        originalRateCents: Int64? = nil,
        originalMiles: Double? = nil
    ) {
        self.id = id
        self.tripId = tripId
        self.date = date
        self.totalRateCents = totalRateCents
        self.totalMiles = totalMiles
        self.pointA = pointA
        self.pointB = pointB
        self.puCount = puCount
        self.delCount = delCount
        self.weekNumber = weekNumber
        self.year = year
        self.rawMessage = rawMessage
        self.parsedAt = parsedAt
        self.updatedAt = updatedAt
        self.route = route
        self.firstPuCityState = firstPuCityState
        self.lastDelCityState = lastDelCityState
        self.durationDays = durationDays
        self.paceCents = paceCents
        self.stopCount = stopCount
        self.isDispute = isDispute
        self.disputeResponseDate = disputeResponseDate
        self.disputeCompleted = disputeCompleted
        self.disputeAmountCents = disputeAmountCents
        self.disputeApplyToLoad = disputeApplyToLoad
        self.disputeAmountApplied = disputeAmountApplied
        self.actualFinishDate = actualFinishDate
        self.stops = stops
        self.penalties = penalties
        self.equipmentType = equipmentType
        self.deadheadMiles = deadheadMiles
        self.isCancelled = isCancelled
        self.cancelledAt = cancelledAt
        self.originalRateCents = originalRateCents
        self.originalMiles = originalMiles
    }
}
