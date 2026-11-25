import Foundation

/// Journal rows → the fields the map aggregator is allowed to see.
enum MapLoadAdapter {
    static func inputs(from loads: [Load]) -> [MapLoadInput] {
        let extras = BackupIdentityStore.standard().load().loadExtras
        return loads.map { load in
            let extra = extras[load.id.uuidString]
            return MapLoadInput(
                pointA: load.pointA ?? "",
                pointB: load.pointB ?? "",
                totalRateDollars: load.totalRate,
                totalMiles: load.totalMiles,
                deadheadMiles: load.deadheadMiles > 0 ? load.deadheadMiles : (extra?.deadheadMiles ?? 0),
                parsedAtMillis: millis(load.parsedAt),
                updatedAtMillis: millis(load.updatedAt),
                filedOnISO: isoDay(load.date),
                equipmentType: load.equipmentType ?? extra?.equipmentType
            )
        }
    }

    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func nowMillis(_ date: Date = Date()) -> Int64 {
        millis(date)
    }

    private static func isoDay(_ date: Date) -> String {
        let zone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return DateFormatCache.string(
            from: date,
            pattern: "yyyy-MM-dd",
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            timeZone: zone
        )
    }
}
