import Foundation

public struct BackupDiesel: Equatable, Sendable {
    public var id: Int
    public var weekNumber: Int
    public var year: Int
    public var weekLabel: String
    public var weekStartDate: String
    public var weekEndDate: String
    public var totalAmountCents: Int64
    public var gallons: Double?
    /// Nullable `UnitPrice` is boxed. Gson writes `{"thousandths":…}`.
    public var pricePerGallonThousandths: Int64?
    public var discountPricePerGallonThousandths: Int64?
    public var location: String?
    public var rawExtractedText: String
    public var sourceFileName: String?
    public var addedAt: Int64

    public init(
        id: Int = 0,
        weekNumber: Int = 0,
        year: Int = 0,
        weekLabel: String = "",
        weekStartDate: String = "",
        weekEndDate: String = "",
        totalAmountCents: Int64 = 0,
        gallons: Double? = nil,
        pricePerGallonThousandths: Int64? = nil,
        discountPricePerGallonThousandths: Int64? = nil,
        location: String? = nil,
        rawExtractedText: String = "",
        sourceFileName: String? = nil,
        addedAt: Int64 = 0
    ) {
        self.id = id
        self.weekNumber = weekNumber
        self.year = year
        self.weekLabel = weekLabel
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.totalAmountCents = totalAmountCents
        self.gallons = gallons
        self.pricePerGallonThousandths = pricePerGallonThousandths
        self.discountPricePerGallonThousandths = discountPricePerGallonThousandths
        self.location = location
        self.rawExtractedText = rawExtractedText
        self.sourceFileName = sourceFileName
        self.addedAt = addedAt
    }
}
