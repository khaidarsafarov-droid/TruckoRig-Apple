import Foundation

public struct BackupAppSettings: Equatable, Sendable {
    public var themeModeOrdinal: Int?
    public var languageOrdinal: Int?
    public var reduceMotion: Bool?
    public var oledDark: Bool?
    public var dynamicColor: Bool?
    public var parserAutoUpdate: Bool?
    public var parserPriceThresholdPercent: Double?
    public var quietHoursEnabled: Bool?
    public var quietHoursStart: Int?
    public var quietHoursEnd: Int?
    public var notifyMissingWeek: Bool?
    public var notifyMaintenance: Bool?
    public var lastEquipmentType: String?
    public var weeklyProfitGoal: Double?
    public var rpmMinProfit: Double?
    public var rpmTargetProfit: Double?
    /// Read for old files. Never written. Android does not restore it.
    public var telegramChatId: Int64?
    public var loadWeekStartDay: Int?
    public var dieselWeekStartDay: Int?
    /// Android `distanceUnit`: `mi` or `km`. Absent means the driver has not picked a unit.
    public var distanceUnit: String?

    public init(
        themeModeOrdinal: Int? = nil,
        languageOrdinal: Int? = nil,
        reduceMotion: Bool? = nil,
        oledDark: Bool? = nil,
        dynamicColor: Bool? = nil,
        parserAutoUpdate: Bool? = nil,
        parserPriceThresholdPercent: Double? = nil,
        quietHoursEnabled: Bool? = nil,
        quietHoursStart: Int? = nil,
        quietHoursEnd: Int? = nil,
        notifyMissingWeek: Bool? = nil,
        notifyMaintenance: Bool? = nil,
        lastEquipmentType: String? = nil,
        weeklyProfitGoal: Double? = nil,
        rpmMinProfit: Double? = nil,
        rpmTargetProfit: Double? = nil,
        telegramChatId: Int64? = nil,
        loadWeekStartDay: Int? = nil,
        dieselWeekStartDay: Int? = nil,
        distanceUnit: String? = nil
    ) {
        self.themeModeOrdinal = themeModeOrdinal
        self.languageOrdinal = languageOrdinal
        self.reduceMotion = reduceMotion
        self.oledDark = oledDark
        self.dynamicColor = dynamicColor
        self.parserAutoUpdate = parserAutoUpdate
        self.parserPriceThresholdPercent = parserPriceThresholdPercent
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.notifyMissingWeek = notifyMissingWeek
        self.notifyMaintenance = notifyMaintenance
        self.lastEquipmentType = lastEquipmentType
        self.weeklyProfitGoal = weeklyProfitGoal
        self.rpmMinProfit = rpmMinProfit
        self.rpmTargetProfit = rpmTargetProfit
        self.telegramChatId = telegramChatId
        self.loadWeekStartDay = loadWeekStartDay
        self.dieselWeekStartDay = dieselWeekStartDay
        self.distanceUnit = distanceUnit
    }
}
