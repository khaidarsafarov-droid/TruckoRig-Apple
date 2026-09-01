import Foundation
@testable import TruckoRigDomain

/// Fixed timezone so parsed instants and week boundaries are reproducible on any machine.
let testTimeZone = TimeZone(identifier: "America/New_York") ?? .current

func makeDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 12,
    _ minute: Int = 0,
    timeZone: TimeZone = testTimeZone
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
}

func isoDay(_ date: Date?, timeZone: TimeZone = testTimeZone) -> String? {
    guard let date else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = components.year, let month = components.month, let day = components.day else { return nil }
    return String(format: "%04d-%02d-%02d", year, month, day)
}

extension LoadSummary {
    /// Load spanning `[start, end]` days in the test timezone.
    static func spanning(
        rate: Double,
        miles: Double = 0,
        from start: Date?,
        to end: Date?,
        finish: Date? = nil
    ) -> LoadSummary {
        LoadSummary(
            tripId: "T-TEST",
            totalRate: rate,
            totalMiles: miles,
            firstPickupAt: start,
            lastDeliveryAt: end,
            actualFinishAt: finish
        )
    }
}
