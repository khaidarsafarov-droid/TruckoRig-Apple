import Foundation

/// Turns a week's loads and the driver's gross goal into everything the goal screen shows.
public struct WeeklyGoalCalculator: Sendable {
    private let week: TruckingWeek
    private let labels: WeekLabelFormatter

    public init(week: TruckingWeek = TruckingWeek(), locale: Locale = .current) {
        self.week = week
        self.labels = WeekLabelFormatter(week: week, locale: locale)
    }

    /// - Parameter sqlGross: Room's week aggregate, when the caller has one. Android takes
    ///   `max(sqlGross, loadGross)` because the SQL sum misses `weekNumber = 0` rows that the
    ///   in-memory filter still includes. Pass `nil` when there is no separate SQL snapshot.
    public func calculate(
        target: Double,
        loads: [LoadSummary],
        for ref: WeekRef,
        sqlGross: Double? = nil,
        now: Date = Date()
    ) -> WeeklyGoalProgress {
        let totals = LoadTotals.of(loads)
        let loadGross = MoneyCents.fromDollars(totals.totalRate)
        let sql = MoneyCents.fromDollars(sqlGross ?? 0)
        let current = max(sql, loadGross)
        let goal = MoneyCents.fromDollars(target)
        let isCurrentWeek = ref == week.currentWeek(now: now)
        let daysActive = week.daysActive(in: ref, now: now)
        let daysRemaining = week.daysRemaining(in: ref, now: now)

        let onRoad = onRoadDays(loads: loads, ref: ref, now: now)
        let totalActiveDays = (Double(onRoad) * 10).rounded() / 10
        let actual = onRoad > 0 ? current.dividedBy(onRoad) : .zero

        // A closed week has no days left to spread the gap over, so "needed per day" would
        // otherwise collapse into the entire remaining goal.
        let dailyTargetNeeded: MoneyCents = isCurrentWeek
            ? GoalMoneyMath.dailyTarget(goal: goal, totalGross: current, daysRemaining: daysRemaining)
            : .zero
        let expected = GoalMoneyMath.expectedGrossByNow(goal: goal, daysActive: daysActive)

        return WeeklyGoalProgress(
            targetAmount: goal.dollars,
            currentGross: current.dollars,
            progressPercent: progressPercent(gross: current, target: goal),
            remainingAmount: (goal - current).coerceAtLeast(.zero).dollars,
            daysActiveCalendar: daysActive,
            daysRemainingInWeek: daysRemaining,
            totalActiveDays: totalActiveDays,
            actualDailyYield: actual.dollars,
            dailyTargetNeeded: dailyTargetNeeded.dollars,
            expectedGrossByNow: expected.dollars,
            paceStatus: paceStatus(
                target: goal,
                gross: current,
                isCurrentWeek: isCurrentWeek,
                loadsCount: loads.count,
                actualDailyYield: actual,
                dailyTargetNeeded: dailyTargetNeeded
            ),
            weekLabel: labels.label(for: ref),
            weekNumber: ref.weekNumber,
            year: ref.year,
            loadsCount: totals.loadCount,
            totalMiles: MoneyCents.fromDollars(totals.totalMiles).dollars
        )
    }

    private func onRoadDays(loads: [LoadSummary], ref: WeekRef, now: Date) -> Int {
        guard let start = week.startDate(of: ref), let end = week.endDate(of: ref) else { return 0 }
        return OnRoadCalendar.days(
            loads: loads,
            weekStart: start,
            weekEnd: end,
            today: now,
            calendar: week.calendar
        )
    }

    public func calculateCurrentWeek(
        target: Double,
        loads: [LoadSummary],
        now: Date = Date()
    ) -> WeeklyGoalProgress {
        let ref = week.currentWeek(now: now)
        return calculate(target: target, loads: loads, for: ref, now: now)
    }

    private func progressPercent(gross: MoneyCents, target: MoneyCents) -> Double {
        guard target.cents > 0 else { return 0 }
        return min(100, Double(gross.cents) / Double(target.cents) * 100)
    }

    private func paceStatus(
        target: MoneyCents,
        gross: MoneyCents,
        isCurrentWeek: Bool,
        loadsCount: Int,
        actualDailyYield: MoneyCents,
        dailyTargetNeeded: MoneyCents
    ) -> PaceStatus {
        guard target.cents > 0 else { return .behind }
        if gross >= target { return .goalMet }
        // Closed weeks are binary: the goal was met or it was not. Mid-week pace bands are noise.
        guard isCurrentWeek else { return .behind }
        guard loadsCount > 0, actualDailyYield.cents > 0 else { return .behind }
        if actualDailyYield >= dailyTargetNeeded.scaledBy(1.05) { return .ahead }
        if actualDailyYield >= dailyTargetNeeded.scaledBy(0.92) { return .onTrack }
        return .behind
    }
}
