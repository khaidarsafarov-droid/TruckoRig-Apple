import Foundation

/// Days the driver was actually on the road inside a reporting week.
///
/// Port of Android `LoadYieldCalculator.onRoadDays` / `coveredDates`. The window is the load's
/// pickup through its own finish. When the next load is picked up sooner, the earlier load ends
/// on that pickup day. The same calendar day is never counted twice, and nothing past `today`
/// or outside the week is counted.
public enum OnRoadCalendar {

    public static func days(
        loads: [LoadSummary],
        weekStart: Date,
        weekEnd: Date,
        today: Date,
        calendar: Calendar
    ) -> Int {
        let startDay = calendar.startOfDay(for: weekStart)
        let endDay = calendar.startOfDay(for: weekEnd)
        let todayDay = calendar.startOfDay(for: today)
        if loads.isEmpty || todayDay < startDay { return 0 }
        let last = todayDay < endDay ? todayDay : endDay
        return coveredDates(loads, through: last, calendar: calendar)
            .filter { $0 >= startDay && $0 <= endDay }
            .count
    }

    public static func coveredDates(
        _ loads: [LoadSummary],
        through: Date,
        calendar: Calendar
    ) -> Set<Date> {
        let throughDay = calendar.startOfDay(for: through)
        let ordered = loads.compactMap { load -> (LoadSummary, Date)? in
            guard let start = pickupDay(of: load, calendar: calendar) else { return nil }
            return (load, start)
        }.sorted { $0.1 < $1.1 }

        var covered = Set<Date>()
        for index in ordered.indices {
            let (load, start) = ordered[index]
            if start > throughDay { continue }
            let ownFinish = finishDay(of: load, pickup: start, calendar: calendar)
            let nextPickup = ordered.indices.contains(index + 1) ? ordered[index + 1].1 : nil
            let finish: Date
            if let nextPickup, nextPickup > start, nextPickup < ownFinish {
                finish = nextPickup
            } else {
                finish = ownFinish
            }
            let stop = finish < throughDay ? finish : throughDay
            if stop < start { continue }
            var day = start
            while day <= stop {
                covered.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return covered
    }

    /// Pickup calendar day: first pickup, otherwise the filing date (`load.date`).
    public static func pickupDay(of load: LoadSummary, calendar: Calendar) -> Date? {
        let raw = load.firstPickupAt ?? load.filedOn
        return raw.map { calendar.startOfDay(for: $0) }
    }

    public static func finishDay(of load: LoadSummary, pickup: Date, calendar: Calendar) -> Date {
        let raw = load.actualFinishAt ?? load.lastDeliveryAt ?? pickup
        return calendar.startOfDay(for: raw)
    }
}
