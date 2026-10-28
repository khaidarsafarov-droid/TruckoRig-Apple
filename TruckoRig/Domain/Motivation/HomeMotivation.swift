import Foundation

/// Newcomer checklist. Android hides it after the first load.
public struct ActivationChecklist: Equatable, Sendable {
    public enum Step: String, CaseIterable, Sendable {
        case account
        case profile
        case firstLoad
        case weeklyGoal
        case firstDiesel
    }

    public var steps: [(Step, Bool)]

    public var completedCount: Int { steps.filter(\.1).count }
    public var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(completedCount) / Double(steps.count)
    }

    public static func build(profileComplete: Bool, hasLoad: Bool, hasWeeklyGoal: Bool, hasDiesel: Bool) -> ActivationChecklist {
        ActivationChecklist(steps: [
            (.account, true),
            (.profile, profileComplete),
            (.firstLoad, hasLoad),
            (.weeklyGoal, hasWeeklyGoal),
            (.firstDiesel, hasDiesel),
        ])
    }
}

/// Weekly prompt for drivers who have not subscribed. Same cadence as Android `Day7SurveyPolicy`.
public enum Day7SurveyPolicy {
    public static let cadence: TimeInterval = 7 * 24 * 60 * 60

    public struct Record: Equatable, Sendable {
        public var firstLaunchAt: Date?
        public var lastShownAt: Date?
        public var optedOut: Bool

        public init(firstLaunchAt: Date? = nil, lastShownAt: Date? = nil, optedOut: Bool = false) {
            self.firstLaunchAt = firstLaunchAt
            self.lastShownAt = lastShownAt
            self.optedOut = optedOut
        }
    }

    public static func withFirstLaunch(_ record: Record, now: Date) -> Record {
        var copy = record
        if copy.firstLaunchAt == nil { copy.firstLaunchAt = now }
        return copy
    }

    public static func shouldShow(_ record: Record, now: Date, premiumActive: Bool, calendar: Calendar = .current) -> Bool {
        guard let first = record.firstLaunchAt, !record.optedOut, !premiumActive else { return false }
        if now.timeIntervalSince(first) < cadence { return false }
        guard let last = record.lastShownAt else { return true }
        if calendar.isDate(last, inSameDayAs: now) { return false }
        return now.timeIntervalSince(last) >= cadence
    }

    public static func recordDisplay(_ record: Record, now: Date) -> Record {
        var copy = record
        if let last = record.lastShownAt, now.timeIntervalSince(last) < cadence { return record }
        copy.lastShownAt = now
        return copy
    }

    public static func optOut(_ record: Record) -> Record {
        var copy = record
        copy.optedOut = true
        return copy
    }
}
