import Foundation
import Observation

/// Week selection and goal editing for the goal tab.
@Observable
final class WeeklyGoalViewModel {

    /// `nil` means "the week we are in right now", so the screen follows the clock across midnight
    /// on Saturday instead of pinning to a stale week.
    private var selectedWeek: WeekRef?
    var isEditingGoal = false
    var goalInput: Double = 0

    func week(in calendar: TruckingWeek, now: Date = Date()) -> WeekRef {
        selectedWeek ?? calendar.currentWeek(now: now)
    }

    func isCurrentWeek(in calendar: TruckingWeek, now: Date = Date()) -> Bool {
        week(in: calendar, now: now) == calendar.currentWeek(now: now)
    }

    func step(_ delta: Int, in calendar: TruckingWeek, now: Date = Date()) {
        let next = calendar.shift(week(in: calendar, now: now), by: delta)
        selectedWeek = next == calendar.currentWeek(now: now) ? nil : next
    }

    func resetToCurrentWeek() {
        selectedWeek = nil
    }

    /// Loads that settle in `week`.
    func loads(_ loads: [Load], in week: WeekRef) -> [Load] {
        loads.filter { $0.weekNumber == week.weekNumber && $0.year == week.year }
    }

    func progress(
        loads: [Load],
        target: Double,
        calendar: TruckingWeek,
        locale: Locale = .current,
        now: Date = Date()
    ) -> WeeklyGoalProgress {
        let week = week(in: calendar, now: now)
        let calculator = WeeklyGoalCalculator(week: calendar, locale: locale)
        return calculator.calculate(
            target: target,
            loads: self.loads(loads, in: week).map(\.summary),
            for: week,
            now: now
        )
    }
}

extension PaceStatus {
    var title: LocalizedStringResource {
        switch self {
        case .goalMet: return "goal.status.met"
        case .ahead: return "goal.status.ahead"
        case .onTrack: return "goal.status.onTrack"
        case .behind: return "goal.status.behind"
        }
    }

    var systemImage: String {
        switch self {
        case .goalMet: return "checkmark.seal.fill"
        case .ahead: return "arrow.up.right.circle.fill"
        case .onTrack: return "equal.circle.fill"
        case .behind: return "arrow.down.right.circle.fill"
        }
    }
}
