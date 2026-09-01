import Foundation

/// How the week is tracking against the driver's gross goal.
public enum PaceStatus: String, Sendable {
    case goalMet
    case ahead
    case onTrack
    case behind
}

/// Everything the weekly goal screen renders, computed in one pass.
public struct WeeklyGoalProgress: Equatable, Sendable {
    public var targetAmount: Double
    public var currentGross: Double
    /// 0…100.
    public var progressPercent: Double
    public var remainingAmount: Double
    /// Calendar days from the week start through today, used for the ring marker.
    public var daysActiveCalendar: Int
    public var daysRemainingInWeek: Int
    /// Sum of per-load PU→DEL durations, in fractional days.
    public var totalActiveDays: Double
    /// Gross divided by days actually spent in transit.
    public var actualDailyYield: Double
    /// `(goal − gross) / calendar days remaining`; zero for closed weeks.
    public var dailyTargetNeeded: Double
    public var expectedGrossByNow: Double
    public var paceStatus: PaceStatus
    public var weekLabel: String
    public var weekNumber: Int
    public var year: Int
    public var loadsCount: Int
    public var totalMiles: Double

    public init(
        targetAmount: Double = 0,
        currentGross: Double = 0,
        progressPercent: Double = 0,
        remainingAmount: Double = 0,
        daysActiveCalendar: Int = 0,
        daysRemainingInWeek: Int = 0,
        totalActiveDays: Double = 0,
        actualDailyYield: Double = 0,
        dailyTargetNeeded: Double = 0,
        expectedGrossByNow: Double = 0,
        paceStatus: PaceStatus = .behind,
        weekLabel: String = "",
        weekNumber: Int = 0,
        year: Int = 0,
        loadsCount: Int = 0,
        totalMiles: Double = 0
    ) {
        self.targetAmount = targetAmount
        self.currentGross = currentGross
        self.progressPercent = progressPercent
        self.remainingAmount = remainingAmount
        self.daysActiveCalendar = daysActiveCalendar
        self.daysRemainingInWeek = daysRemainingInWeek
        self.totalActiveDays = totalActiveDays
        self.actualDailyYield = actualDailyYield
        self.dailyTargetNeeded = dailyTargetNeeded
        self.expectedGrossByNow = expectedGrossByNow
        self.paceStatus = paceStatus
        self.weekLabel = weekLabel
        self.weekNumber = weekNumber
        self.year = year
        self.loadsCount = loadsCount
        self.totalMiles = totalMiles
    }

    /// 0…1 for progress bars.
    public var progressFraction: Double { min(1, max(0, progressPercent / 100)) }
}
