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
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
