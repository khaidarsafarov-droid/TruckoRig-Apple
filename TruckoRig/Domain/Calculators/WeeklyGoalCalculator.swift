import Foundation

/// Turns a week's loads and the driver's gross goal into everything the goal screen shows.
public struct WeeklyGoalCalculator: Sendable {
    private let week: TruckingWeek
    private let labels: WeekLabelFormatter

    public init(week: TruckingWeek = TruckingWeek(), locale: Locale = .current) {
        self.week = week
        self.labels = WeekLabelFormatter(week: week, locale: locale)
    }

    public func calculate(
        target: Double,
        loads: [LoadSummary],
        for ref: WeekRef,
        now: Date = Date()
    ) -> WeeklyGoalProgress {
        let totals = LoadTotals.of(loads)
        let currentGross = GoalMoneyMath.roundMoney(totals.totalRate)
        let isCurrentWeek = ref == week.currentWeek(now: now)
        let daysActive = week.daysActive(in: ref, now: now)
        let daysRemaining = week.daysRemaining(in: ref, now: now)

        let totalActiveDays = LoadYieldCalculator.totalActiveDays(loads)
        let actualDailyYield = LoadYieldCalculator.actualDailyYield(loads)

        // A closed week has no days left to spread the gap over, so "needed per day" would
        // otherwise collapse into the entire remaining goal.
        let dailyTargetNeeded = isCurrentWeek
            ? GoalMoneyMath.dailyTarget(goal: target, totalGross: currentGross, daysRemaining: daysRemaining)
            : 0

        return WeeklyGoalProgress(
            targetAmount: GoalMoneyMath.roundMoney(target),
            currentGross: currentGross,
            progressPercent: progressPercent(gross: currentGross, target: target),
            remainingAmount: GoalMoneyMath.roundMoney(max(0, target - currentGross)),
            daysActiveCalendar: daysActive,
            daysRemainingInWeek: daysRemaining,
            totalActiveDays: (totalActiveDays * 10).rounded() / 10,
            actualDailyYield: actualDailyYield,
            dailyTargetNeeded: dailyTargetNeeded,
            expectedGrossByNow: GoalMoneyMath.expectedGrossByNow(goal: target, daysActive: daysActive),
            paceStatus: paceStatus(
                target: target,
                gross: currentGross,
                isCurrentWeek: isCurrentWeek,
                loadsCount: loads.count,
                actualDailyYield: actualDailyYield,
                dailyTargetNeeded: dailyTargetNeeded
            ),
            weekLabel: labels.label(for: ref),
            weekNumber: ref.weekNumber,
            year: ref.year,
            loadsCount: totals.loadCount,
            totalMiles: GoalMoneyMath.roundMoney(totals.totalMiles)
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

    private func progressPercent(gross: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return min(100, gross / target * 100)
    }

    private func paceStatus(
        target: Double,
        gross: Double,
        isCurrentWeek: Bool,
        loadsCount: Int,
        actualDailyYield: Double,
        dailyTargetNeeded: Double
    ) -> PaceStatus {
        guard target > 0 else { return .behind }
        if gross >= target { return .goalMet }
        // Closed weeks are binary: the goal was met or it was not. Mid-week pace bands are noise.
        guard isCurrentWeek else { return .behind }
        guard loadsCount > 0, actualDailyYield > 0 else { return .behind }
        if actualDailyYield >= dailyTargetNeeded * 1.05 { return .ahead }
        if actualDailyYield >= dailyTargetNeeded * 0.92 { return .onTrack }
        return .behind
    }
}
