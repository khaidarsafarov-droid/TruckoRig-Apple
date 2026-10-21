import Foundation

/// The few numbers the home-screen widget paints.
///
/// The widget extension never opens the SQLCipher journal. The app writes this snapshot into the
/// shared App Group after it has already computed the week with `WeeklyGoalCalculator` and
/// `GoalMoneyMath`. New fields decode as defaults so a snapshot written by an older build still
/// loads.
public struct WidgetGoalSnapshot: Codable, Equatable, Sendable {
    public var target: Double
    public var gross: Double
    public var remaining: Double
    /// 0…100, the same scale as `WeeklyGoalProgress.progressPercent`.
    public var progressPercent: Double
    /// Weekly gross ÷ miles. Zero when the week has no miles.
    public var rpm: Double
    public var dailyTargetNeeded: Double
    /// Gross ÷ on-road days. Android `WidgetStats.goalActualDailyYield`.
    public var actualDailyYield: Double
    public var daysRemaining: Int
    public var paceStatus: String
    public var weekLabel: String
    /// Split-header range, e.g. `18 – 24 окт`.
    public var weekRange: String
    public var updatedAt: Date

    public init(
        target: Double,
        gross: Double,
        remaining: Double,
        progressPercent: Double,
        rpm: Double,
        dailyTargetNeeded: Double,
        actualDailyYield: Double = 0,
        daysRemaining: Int,
        paceStatus: String,
        weekLabel: String,
        weekRange: String,
        updatedAt: Date
    ) {
        self.target = target
        self.gross = gross
        self.remaining = remaining
        self.progressPercent = progressPercent
        self.rpm = rpm
        self.dailyTargetNeeded = dailyTargetNeeded
        self.actualDailyYield = actualDailyYield
        self.daysRemaining = daysRemaining
        self.paceStatus = paceStatus
        self.weekLabel = weekLabel
        self.weekRange = weekRange
        self.updatedAt = updatedAt
    }

    /// Gallery and preview numbers from the approved widget mockup.
    public static let placeholder = WidgetGoalSnapshot(
        target: 13_000,
        gross: 11_606,
        remaining: 1_394,
        progressPercent: 89,
        rpm: 2.82,
        dailyTargetNeeded: 0,
        actualDailyYield: 0,
        daysRemaining: 2,
        paceStatus: PaceStatus.onTrack.rawValue,
        weekLabel: "Oct 18 – Oct 24, 2025",
        weekRange: "18 – 24 окт",
        updatedAt: Date(timeIntervalSince1970: 1_761_000_000)
    )

    public var progressFraction: Double {
        min(1, max(0, progressPercent / 100))
    }

    public var hasGoal: Bool { target > 0 }

    private enum CodingKeys: String, CodingKey {
        case target, gross, remaining, progressPercent, rpm
        case dailyTargetNeeded, actualDailyYield, daysRemaining, paceStatus, weekLabel, weekRange, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try container.decode(Double.self, forKey: .target)
        gross = try container.decode(Double.self, forKey: .gross)
        dailyTargetNeeded = try container.decodeIfPresent(Double.self, forKey: .dailyTargetNeeded) ?? 0
        actualDailyYield = try container.decodeIfPresent(Double.self, forKey: .actualDailyYield) ?? 0
        daysRemaining = try container.decodeIfPresent(Int.self, forKey: .daysRemaining) ?? 0
        paceStatus = try container.decodeIfPresent(String.self, forKey: .paceStatus) ?? PaceStatus.behind.rawValue
        weekLabel = try container.decodeIfPresent(String.self, forKey: .weekLabel) ?? ""
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        remaining = try container.decodeIfPresent(Double.self, forKey: .remaining) ?? max(0, target - gross)
        if let stored = try container.decodeIfPresent(Double.self, forKey: .progressPercent) {
            progressPercent = stored
        } else if target > 0 {
            progressPercent = min(100, gross / target * 100)
        } else {
            progressPercent = 0
        }
        rpm = try container.decodeIfPresent(Double.self, forKey: .rpm) ?? 0
        weekRange = try container.decodeIfPresent(String.self, forKey: .weekRange) ?? weekLabel
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(gross, forKey: .gross)
        try container.encode(remaining, forKey: .remaining)
        try container.encode(progressPercent, forKey: .progressPercent)
        try container.encode(rpm, forKey: .rpm)
        try container.encode(dailyTargetNeeded, forKey: .dailyTargetNeeded)
        try container.encode(actualDailyYield, forKey: .actualDailyYield)
        try container.encode(daysRemaining, forKey: .daysRemaining)
        try container.encode(paceStatus, forKey: .paceStatus)
        try container.encode(weekLabel, forKey: .weekLabel)
        try container.encode(weekRange, forKey: .weekRange)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Turns a calculated week into the snapshot the widget reads.
public enum WidgetSnapshotBuilder {

    public static func make(
        progress: WeeklyGoalProgress,
        weekStart: Date,
        weekEnd: Date,
        calendar: Calendar,
        locale: Locale,
        now: Date = Date()
    ) -> WidgetGoalSnapshot {
        let miles = progress.totalMiles
        let rpm = miles > 0 ? progress.currentGross / miles : 0
        return WidgetGoalSnapshot(
            target: progress.targetAmount,
            gross: progress.currentGross,
            remaining: progress.remainingAmount,
            progressPercent: progress.progressPercent,
            rpm: rpm,
            dailyTargetNeeded: progress.dailyTargetNeeded,
            actualDailyYield: progress.actualDailyYield,
            daysRemaining: progress.daysRemainingInWeek,
            paceStatus: progress.paceStatus.rawValue,
            weekLabel: progress.weekLabel,
            weekRange: SplitWeekRange.format(
                start: weekStart,
                end: weekEnd,
                calendar: calendar,
                locale: locale
            ),
            updatedAt: now
        )
    }
}

/// Widget and analytics money, always US-formatted, matching Android `MoneyFormat` / `WidgetStatsFormatter`.
public enum USMoneyFormat {

    public static func currency(_ value: Double, fractionDigits: Int = 0) -> String {
        grouped(value, fractionDigits: fractionDigits, style: .currency)
    }

    public static func number(_ value: Double, fractionDigits: Int = 0) -> String {
        grouped(value, fractionDigits: fractionDigits, style: .decimal)
    }

    /// US grouping. `String(format:)` does not honor `%,` on every Foundation, so this uses
    /// `NumberFormatter` and stays `$11,606` on both Apple and the Linux test runner.
    private static func grouped(_ value: Double, fractionDigits: Int, style: NumberFormatter.Style) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = style
        if style == .currency {
            formatter.currencyCode = "USD"
        }
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// `$2.82` — the value inside the RPM pill.
    public static func rpm(_ value: Double) -> String {
        String(format: "$%.2f", locale: Locale(identifier: "en_US"), value)
    }

    /// `$2.94/mi`.
    public static func rpmPerMile(_ value: Double) -> String {
        String(format: "$%.2f/mi", locale: Locale(identifier: "en_US"), value)
    }

    /// `850 mi`.
    public static func miles(_ value: Double) -> String {
        "\(number(value)) mi"
    }

    /// `89%` or `72.4%`. Drops a decimal that would only be noise, matching `formatRingPercent`.
    public static func ringPercent(_ progress: Double) -> String {
        let clamped = min(100, max(0, progress))
        let nearest = clamped.rounded()
        if abs(clamped - nearest) < 0.05 {
            return String(format: "%.0f%%", locale: Locale(identifier: "en_US"), nearest)
        }
        return String(format: "%.1f%%", locale: Locale(identifier: "en_US"), clamped)
    }
}

/// `18 – 24 окт` inside one month, otherwise `28 дек – 3 янв`.
public enum SplitWeekRange {

    public static func format(start: Date, end: Date, calendar: Calendar, locale: Locale) -> String {
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
            && calendar.component(.year, from: start) == calendar.component(.year, from: end)
        if sameMonth {
            return "\(startDay) – \(endDay) \(month(end, calendar: calendar, locale: locale))"
        }
        return "\(startDay) \(month(start, calendar: calendar, locale: locale)) – \(endDay) \(month(end, calendar: calendar, locale: locale))"
    }

    /// `окт 18 – окт 24`, the home week card caption.
    public static func homeCaption(start: Date, end: Date, calendar: Calendar, locale: Locale) -> String {
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        return "\(month(start, calendar: calendar, locale: locale)) \(startDay) – \(month(end, calendar: calendar, locale: locale)) \(endDay)"
    }

    private static func month(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "LLL"
        return formatter.string(from: date)
            .replacingOccurrences(of: ".", with: "")
            .lowercased(with: locale)
    }
}
