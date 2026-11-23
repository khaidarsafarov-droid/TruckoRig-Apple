import Foundation

public struct BackupPaycheck: Equatable, Sendable {
    public var id: Int
    public var weekNumber: Int
    public var year: Int
    public var weekLabel: String
    public var weekStartDate: String
    public var weekEndDate: String
    public var driverName: String?
    /// Nullable `Money` is boxed. Gson writes `{"cents":…}`.
    public var grossAmountCents: Int64?
    public var netAmountCents: Int64
    public var rawExtractedText: String
    public var sourceFileName: String?
    public var addedAt: Int64
    public var sourceFilePath: String?

    public init(
        id: Int = 0,
        weekNumber: Int = 0,
        year: Int = 0,
        weekLabel: String = "",
        weekStartDate: String = "",
        weekEndDate: String = "",
        driverName: String? = nil,
        grossAmountCents: Int64? = nil,
        netAmountCents: Int64 = 0,
        rawExtractedText: String = "",
        sourceFileName: String? = nil,
        addedAt: Int64 = 0,
        sourceFilePath: String? = nil
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.year = year
        self.weekLabel = weekLabel
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.driverName = driverName
        self.grossAmountCents = grossAmountCents
        self.netAmountCents = netAmountCents
        self.rawExtractedText = rawExtractedText
        self.sourceFileName = sourceFileName
        self.addedAt = addedAt
        self.sourceFilePath = sourceFilePath
    }
}
