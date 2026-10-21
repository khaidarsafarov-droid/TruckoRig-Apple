import Foundation

/// One row in the widget Camera/Scan load picker.
public struct AttachLoadCandidate: Equatable, Sendable {
    public var id: String
    public var tripId: String
    public var date: String
    public var parsedAt: Date
    public var pointA: String
    public var pointB: String
    public var route: String
    public var weekNumber: Int
    public var year: Int

    public init(
        id: String,
        tripId: String,
        date: String,
        parsedAt: Date,
        pointA: String,
        pointB: String,
        route: String,
        weekNumber: Int,
        year: Int
    ) {
        self.id = id
        self.tripId = tripId
        self.date = date
        self.parsedAt = parsedAt
        self.pointA = pointA
        self.pointB = pointB
        self.route = route
        self.weekNumber = weekNumber
        self.year = year
    }
}

/// Quick list = last 3 loads of the current trucking week. Port of `AttachLoadSelection`.
public enum AttachLoadSelection {
    public static let quickPickLimit = 3

    public static func quickPickThisWeek(
        loads: [AttachLoadCandidate],
        weekNumber: Int,
        year: Int,
        limit: Int = quickPickLimit
    ) -> [AttachLoadCandidate] {
        guard limit > 0 else { return [] }
        return loads
            .filter { $0.weekNumber == weekNumber && $0.year == year }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.parsedAt > rhs.parsedAt
            }
            .prefix(limit)
            .map { $0 }
    }

    public static func filterBrowse(loads: [AttachLoadCandidate], query: String) -> [AttachLoadCandidate] {
        let sorted = loads.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.parsedAt > rhs.parsedAt
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return sorted }
        let lowered = trimmed.lowercased()
        return sorted.filter { load in
            load.tripId.lowercased().contains(lowered)
                || load.pointA.lowercased().contains(lowered)
                || load.pointB.lowercased().contains(lowered)
                || load.route.lowercased().contains(lowered)
                || load.date.contains(trimmed)
        }
    }
}

/// TODAY / THIS WEEK bounds for the photo gallery. Port of `PhotoGalleryTimeBounds`.
public enum PhotoGalleryTimeBounds {
    public static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = startOfDay(date, calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return next.addingTimeInterval(-0.001)
    }

    public static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysFromStart = (weekday - calendar.firstWeekday + 7) % 7
        let shifted = calendar.date(byAdding: .day, value: -daysFromStart, to: date) ?? date
        return startOfDay(shifted, calendar: calendar)
    }

    public static func isInToday(_ timestamp: Date, now: Date, calendar: Calendar) -> Bool {
        let start = startOfDay(now, calendar: calendar)
        let end = endOfDay(now, calendar: calendar)
        return timestamp >= start && timestamp <= end
    }

    public static func isInThisWeek(_ timestamp: Date, now: Date, calendar: Calendar) -> Bool {
        timestamp >= startOfWeek(now, calendar: calendar)
    }
}
