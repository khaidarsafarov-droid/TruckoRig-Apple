import Foundation
import Observation

/// Week selection and goal editing for the goal tab.
@Observable
final class WeeklyGoalViewModel {

    /// `nil` means "the week we are in right now", so the screen follows the clock across midnight
    /// on Saturday instead of pinning to a stale week.
    private var selectedWeek: WeekRef?
    var isEditingGoal = false
    var goalDraft = ""
    var goalError: String?

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
        locale: Locale = AppLocale.locale,
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

    /// Day rows for the goal card. Booked gross includes loads that have not finished yet.
    func dayPlan(
        loads: [Load],
        progress: WeeklyGoalProgress,
        calendar: TruckingWeek
    ) -> (rows: [DayPlanRow], dailyNeeded: Double) {
        let ref = WeekRef(weekNumber: progress.weekNumber, year: progress.year)
        guard let start = calendar.startDate(of: ref) else { return ([], 0) }
        let buckets = WeekDayGross.centsBySqliteWeekday(
            loads: self.loads(loads, in: ref).map {
                AttributedLoad(pickup: $0.date, finish: $0.effectiveFinishDate, rate: $0.totalRate)
            },
            week: calendar,
            ref: ref
        )
        let booked = WeekDayGross.bookedDollars(buckets)
        let needed = GoalMoneyMath.dailyTarget(
            goal: progress.targetAmount,
            totalGross: booked,
            daysRemaining: progress.daysRemainingInWeek
        )
        let rows = WeeklyDayPlan.rows(
            weekStart: start,
            today: Date(),
            grossCentsBySqliteWeekday: buckets,
            dailyNeeded: MoneyCents.fromDollars(needed),
            calendar: calendar.calendar
        )
        return (rows, needed)
    }
}
