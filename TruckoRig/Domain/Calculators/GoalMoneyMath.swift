import Foundation

/// Money rounding and goal arithmetic shared by the goal screen, widget and analytics.
///
/// The cent math matches Android `GoalMoneyMath`: daily need divides remaining cents half-up,
/// and the ring marker is `(goalCents * days + 3) / 7`.
public enum GoalMoneyMath {

    public static func roundMoney(_ value: Double) -> Double {
        MoneyCents.fromDollars(value).dollars
    }

    public static func dailyTarget(goal: MoneyCents, totalGross: MoneyCents, daysRemaining: Int) -> MoneyCents {
        if goal.cents <= 0 { return .zero }
        let remaining = (goal - totalGross).coerceAtLeast(.zero)
        if remaining.cents <= 0 { return .zero }
        return remaining.dividedBy(max(1, daysRemaining))
    }

    /// Linear plan marker: where a driver on an even pace would be by now.
    public static func expectedGrossByNow(goal: MoneyCents, daysActive: Int) -> MoneyCents {
        if goal.cents <= 0 || daysActive <= 0 { return .zero }
        let days = min(7, daysActive)
        let product = goal.cents * Int64(days)
        let negative = product < 0
        let cents = (abs(product) + 3) / 7
        return MoneyCents(cents: negative ? -cents : cents)
    }

    /// What still has to be earned per remaining calendar day.
    public static func dailyTarget(goal: Double, totalGross: Double, daysRemaining: Int) -> Double {
        dailyTarget(
            goal: MoneyCents.fromDollars(goal),
            totalGross: MoneyCents.fromDollars(totalGross),
            daysRemaining: daysRemaining
        ).dollars
    }

    public static func expectedGrossByNow(goal: Double, daysActive: Int) -> Double {
        expectedGrossByNow(goal: MoneyCents.fromDollars(goal), daysActive: daysActive).dollars
    }
}
