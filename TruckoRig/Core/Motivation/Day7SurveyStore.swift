import Foundation

/// Persists the day-7 survey clock in UserDefaults. Android uses `Day7SurveyStore`.
struct Day7SurveyStore {
    private let defaults: UserDefaults
    private let prefix: String

    init(scope: AccountScope, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.prefix = "truckorig.\(scope.storeKey).day7"
    }

    func load(now: Date) -> Day7SurveyPolicy.Record {
        let first = defaults.object(forKey: prefix + ".first") as? Double
        let last = defaults.object(forKey: prefix + ".last") as? Double
        let record = Day7SurveyPolicy.withFirstLaunch(
            Day7SurveyPolicy.Record(
                firstLaunchAt: first.map { Date(timeIntervalSince1970: $0) },
                lastShownAt: last.map { Date(timeIntervalSince1970: $0) },
                optedOut: defaults.bool(forKey: prefix + ".out")
            ),
            now: now
        )
        save(record)
        return record
    }

    func save(_ record: Day7SurveyPolicy.Record) {
        if let first = record.firstLaunchAt {
            defaults.set(first.timeIntervalSince1970, forKey: prefix + ".first")
        }
        if let last = record.lastShownAt {
            defaults.set(last.timeIntervalSince1970, forKey: prefix + ".last")
        } else {
            defaults.removeObject(forKey: prefix + ".last")
        }
        defaults.set(record.optedOut, forKey: prefix + ".out")
    }
}
