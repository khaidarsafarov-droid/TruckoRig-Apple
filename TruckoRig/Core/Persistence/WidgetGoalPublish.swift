import Foundation

extension WidgetBridge {

    /// Writes the current week's goal numbers for the home-screen widget.
    ///
    /// The SQLCipher key stays in this process. Only the finished numbers are written to the App Group.
    @MainActor
    static func publishWeek(loads: [Load], settings: AppSettings, now: Date = Date()) {
        let week = settings.truckingWeek
        let ref = week.currentWeek(now: now)
        let weekLoads = loads.filter { $0.weekNumber == ref.weekNumber && $0.year == ref.year }
        let locale = snapshotLocale(settings)
        let progress = WeeklyGoalCalculator(week: week, locale: locale).calculate(
            target: settings.weeklyGoal,
            loads: weekLoads.map(\.summary),
            for: ref,
            now: now
        )
        guard let start = week.startDate(of: ref), let end = week.endDate(of: ref) else { return }
        let snapshot = WidgetSnapshotBuilder.make(
            progress: progress,
            weekStart: start,
            weekEnd: end,
            calendar: week.calendar,
            locale: locale,
            now: now
        )
        publish(snapshot)
    }

    private static func snapshotLocale(_ settings: AppSettings) -> Locale {
        if let identifier = settings.language.localeIdentifier {
            return Locale(identifier: identifier)
        }
        return .current
    }
}
