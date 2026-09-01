import Foundation

/// Money rounding and goal arithmetic shared by the goal screen, widget and analytics.
public enum GoalMoneyMath {

    public static func roundMoney(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * 100).rounded() / 100
    }

    /// What still has to be earned per remaining calendar day.
    public static func dailyTarget(goal: Double, totalGross: Double, daysRemaining: Int) -> Double {
        guard goal > 0 else { return 0 }
        let remaining = max(0, goal - totalGross)
        guard remaining > 0 else { return 0 }
        return roundMoney(remaining / Double(max(1, daysRemaining)))
    }

    /// Linear plan marker: where a driver on an even pace would be by now.
    public static func expectedGrossByNow(goal: Double, daysActive: Int) -> Double {
        guard goal > 0, daysActive > 0 else { return 0 }
        return roundMoney(goal * Double(min(7, daysActive)) / 7)
    }
}
