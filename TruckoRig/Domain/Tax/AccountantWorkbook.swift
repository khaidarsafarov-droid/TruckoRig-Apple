import Foundation

/// One load row in the accountant workbook. `onDutyDays` is
/// `PerDiemCalculator.uniqueOnDutyDates` for that load inside the export year.
public struct AccountantWorkbookLoad: Equatable, Sendable {
    public var date: String
    public var tripId: String
    public var route: String
    public var rate: MoneyCents
    public var miles: Double
    public var onDutyDays: Int

    public init(
        date: String,
        tripId: String,
        route: String,
        rate: MoneyCents,
        miles: Double,
        onDutyDays: Int
    ) {
        self.date = date
        self.tripId = tripId
        self.route = route
        self.rate = rate
        self.miles = miles
        self.onDutyDays = onDutyDays
    }
}

/// One diesel row. Prices are dollars. `nil` is an empty cell; a real zero stays numeric, matching Android.
public struct AccountantWorkbookDiesel: Equatable, Sendable {
    public var weekNumber: Int
    public var year: Int
    public var weekStartDate: String
    public var weekEndDate: String
    public var totalAmount: MoneyCents
    public var gallons: Double?
    public var pricePerGallon: Double?
    public var discountPricePerGallon: Double?
    public var location: String

    public init(
        weekNumber: Int,
        year: Int,
        weekStartDate: String,
        weekEndDate: String,
        totalAmount: MoneyCents,
        gallons: Double?,
        pricePerGallon: Double?,
        discountPricePerGallon: Double?,
        location: String
    ) {
        self.weekNumber = weekNumber
        self.year = year
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.totalAmount = totalAmount
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.discountPricePerGallon = discountPricePerGallon
        self.location = location
    }
}

public struct AccountantWorkbookMaintenance: Equatable, Sendable {
    public var serviceDate: String
    public var serviceName: String
    public var description: String
    public var amount: MoneyCents

    public init(serviceDate: String, serviceName: String, description: String, amount: MoneyCents) {
        self.serviceDate = serviceDate
        self.serviceName = serviceName
        self.description = description
        self.amount = amount
    }
}

/// Year-scoped rows for the accountant workbook. Field roles match Android
/// `AccountantWorkbookBuilder.Input`.
public struct AccountantWorkbookInput: Equatable, Sendable {
    public var year: Int
    public var loads: [AccountantWorkbookLoad]
    public var diesel: [AccountantWorkbookDiesel]
    public var perDiemDates: Set<String>
    public var maintenance: [AccountantWorkbookMaintenance]
    public var grossIncome: Double

    public init(
        year: Int,
        loads: [AccountantWorkbookLoad],
        diesel: [AccountantWorkbookDiesel],
        perDiemDates: Set<String>,
        maintenance: [AccountantWorkbookMaintenance],
        grossIncome: Double
    ) {
        self.year = year
        self.loads = loads
        self.diesel = diesel
        self.perDiemDates = perDiemDates
        self.maintenance = maintenance
        self.grossIncome = grossIncome
    }
}

/// Excel workbook with the same sheets, columns, headers, totals and file-name label as
/// Android `AccountantWorkbookBuilder`. The container is OOXML `.xlsx` rather than SpreadsheetML `.xls`.
public enum AccountantWorkbook {
    public static let displayName = "TruckoRig"
    public static let filePrefix = "TruckoRig"

    public static func resolveSections(_ sections: Set<AccountantExportSection>) -> Set<AccountantExportSection> {
        AccountantExportSection.resolve(sections)
    }

    public static func fileLabel(_ sections: Set<AccountantExportSection>) -> String {
        let resolved = resolveSections(sections)
        if resolved.count >= 4 { return "All" }
        if resolved.count == 1, let only = resolved.first {
            switch only {
            case .loads: return "Loads"
            case .diesel: return "Diesel"
            case .perDiem: return "PerDiem"
            case .maintenance: return "Maintenance"
            case .all: return "All"
            }
        }
        return "Custom"
    }

    /// `TruckoRig_Tax_{year}_{label}_{yyyyMMdd}.xlsx`. Android uses the same stem with `.xls`.
    public static func fileName(
        year: Int,
        sections: Set<AccountantExportSection>,
        day: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let stamp = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "\(filePrefix)_Tax_\(year)_\(fileLabel(sections))_\(stamp).xlsx"
    }

    public static func isEmpty(_ input: AccountantWorkbookInput, sections: Set<AccountantExportSection>) -> Bool {
        let resolved = resolveSections(sections)
        return resolved.allSatisfy { section in
            switch section {
            case .loads: return input.loads.isEmpty
            case .diesel: return input.diesel.isEmpty
            case .perDiem: return input.perDiemDates.isEmpty
            case .maintenance: return input.maintenance.isEmpty
            case .all: return true
            }
        }
    }

    public static func sheets(
        input: AccountantWorkbookInput,
        sections requested: Set<AccountantExportSection>
    ) -> [XlsxSheet] {
        let sections = resolveSections(requested)
        var sheets = [summarySheet(input, sections: sections)]
        if sections.contains(.loads) {
            sheets.append(loadsSheet(input))
        }
        if sections.contains(.diesel) {
            sheets.append(dieselSheet(input))
        }
        if sections.contains(.perDiem) {
            sheets.append(perDiemSheet(input))
        }
        if sections.contains(.maintenance) {
            sheets.append(maintenanceSheet(input))
        }
        return sheets
    }

    public static func data(
        input: AccountantWorkbookInput,
        sections: Set<AccountantExportSection>
    ) -> Data {
        XlsxWorkbook.data(sheets: sheets(input: input, sections: sections))
    }

    /// Dollars saved versus list price, in cents, using Android `UnitPrice.timesGallons` rounding.
    /// `nil` (empty cell) when gallons or either price is missing or not positive.
    /// Zero when both prices are positive and the discount is not lower.
    public static func savingsCents(
        gallons: Double?,
        pricePerGallon: Double?,
        discountPricePerGallon: Double?
    ) -> MoneyCents? {
        guard let gallons, gallons > 0,
              let pricePerGallon, pricePerGallon > 0,
              let discountPricePerGallon, discountPricePerGallon > 0
        else { return nil }
        let gap = UnitPricePlain.thousandths(from: pricePerGallon) - UnitPricePlain.thousandths(from: discountPricePerGallon)
        if gap <= 0 { return .zero }
        return UnitPricePlain.timesGallons(thousandths: gap, gallons: gallons)
    }

    private static func summarySheet(
        _ input: AccountantWorkbookInput,
        sections: Set<AccountantExportSection>
    ) -> XlsxSheet {
        let loadsTotal = input.loads.reduce(MoneyCents.zero) { $0 + $1.rate }
        let dieselTotal = input.diesel.reduce(MoneyCents.zero) { $0 + $1.totalAmount }
        let perDiemDays = input.perDiemDates.count
        let perDiemTotal = PerDiemCalculator.amount(dayCount: perDiemDays)
        let maintenanceTotal = input.maintenance.reduce(MoneyCents.zero) { $0 + $1.amount }
        var rows: [[XlsxCell]] = [
            [.text("\(displayName) — отчёт для бухгалтера"), .blank],
            [.text("Год"), integer(input.year)],
            [.text("Валовой доход (paycheck), USD"), money(input.grossIncome)],
            [.blank, .blank],
        ]
        if sections.contains(.loads) {
            rows.append([.text("Грузов"), integer(input.loads.count)])
            rows.append([.text("Сумма ставок грузов, USD"), money(loadsTotal)])
        }
        if sections.contains(.diesel) {
            rows.append([.text("Заправок дизеля"), integer(input.diesel.count)])
            rows.append([.text("Дизель всего, USD"), money(dieselTotal)])
        }
        if sections.contains(.perDiem) {
            rows.append([.text("Дней на рейсах (суточные)"), integer(perDiemDays)])
            rows.append([.text("Ставка суточных, USD/день"), money(PerDiemCalculator.dailyRate)])
            rows.append([.text("Суточные всего, USD"), money(perDiemTotal)])
        }
        if sections.contains(.maintenance) {
            rows.append([.text("Записей ТО"), integer(input.maintenance.count)])
            rows.append([.text("ТО всего, USD"), money(maintenanceTotal)])
        }
        rows.append([.blank, .blank])
        rows.append([
            .text("Подсказка"),
            .text("Каждый лист — отдельная таблица. Откройте в Excel / Google Таблицах. Отправьте через Telegram, WhatsApp или почту."),
        ])
        return XlsxSheet(name: "Сводка", rows: rows, headerRow: false)
    }

    private static func loadsSheet(_ input: AccountantWorkbookInput) -> XlsxSheet {
        let header = ["Дата", "Trip ID", "Маршрут", "Ставка, USD", "Мили", "RPM", "Дней на рейсе"].map {
            XlsxCell.text($0)
        }
        let body = input.loads.sorted { $0.date < $1.date }.map { load -> [XlsxCell] in
            let rpm = load.miles > 0 ? load.rate.dollars / load.miles : 0
            return [
                isoDate(load.date),
                .text(load.tripId),
                .text(load.route),
                money(load.rate),
                miles(load.miles),
                rpmCell(rpm),
                integer(load.onDutyDays),
            ]
        }
        return XlsxSheet(name: "Грузы", rows: [header] + body, headerRow: true)
    }

    private static func dieselSheet(_ input: AccountantWorkbookInput) -> XlsxSheet {
        let header = [
            "Неделя", "Год", "Начало недели", "Конец недели", "Сумма, USD",
            "Галлоны", "Цена / гал", "Цена со скидкой / гал", "Экономия, USD", "Место",
        ].map { XlsxCell.text($0) }
        let body = input.diesel.sorted {
            ($0.year, $0.weekNumber) < ($1.year, $1.weekNumber)
        }.map { fill -> [XlsxCell] in
            let savings = savingsCents(
                gallons: fill.gallons,
                pricePerGallon: fill.pricePerGallon,
                discountPricePerGallon: fill.discountPricePerGallon
            )
            return [
                integer(fill.weekNumber),
                integer(fill.year),
                isoDate(fill.weekStartDate),
                isoDate(fill.weekEndDate),
                money(fill.totalAmount),
                gallons(fill.gallons),
                unitPriceCell(fill.pricePerGallon),
                unitPriceCell(fill.discountPricePerGallon),
                moneyOrBlank(savings),
                .text(fill.location),
            ]
        }
        return XlsxSheet(name: "Дизель", rows: [header] + body, headerRow: true)
    }

    private static func perDiemSheet(_ input: AccountantWorkbookInput) -> XlsxSheet {
        let header = ["Дата на рейсе", "Ставка, USD", "Сумма, USD"].map { XlsxCell.text($0) }
        let rate = money(PerDiemCalculator.dailyRate)
        let body = input.perDiemDates.sorted().map { day -> [XlsxCell] in
            [isoDate(day), rate, rate]
        }
        let total = [
            XlsxCell.text("ИТОГО (\(input.perDiemDates.count) дн.)"),
            rate,
            money(PerDiemCalculator.amount(dayCount: input.perDiemDates.count)),
        ]
        return XlsxSheet(name: "Суточные", rows: [header] + body + [total], headerRow: true)
    }

    private static func maintenanceSheet(_ input: AccountantWorkbookInput) -> XlsxSheet {
        let header = ["Дата ТО", "Услуга", "Описание", "Сумма, USD"].map { XlsxCell.text($0) }
        let body = input.maintenance.map { entry -> [XlsxCell] in
            [isoDate(entry.serviceDate), .text(entry.serviceName), .text(entry.description), money(entry.amount)]
        }
        let total = input.maintenance.reduce(MoneyCents.zero) { $0 + $1.amount }
        return XlsxSheet(
            name: "ТО",
            rows: [header] + body + [[.text("ИТОГО"), .blank, .blank, money(total)]],
            headerRow: true
        )
    }

    private static func isoDate(_ iso: String) -> XlsxCell {
        XlsxCell.date(iso: iso)
    }

    private static func money(_ cents: MoneyCents) -> XlsxCell {
        .number(raw: cents.formatPlain(), format: .money)
    }

    private static func money(_ dollars: Double) -> XlsxCell {
        .number(raw: plain(dollars), format: .money)
    }

    private static func moneyOrBlank(_ cents: MoneyCents?) -> XlsxCell {
        guard let cents else { return .blank }
        return money(cents)
    }

    private static func integer(_ value: Int) -> XlsxCell {
        .number(raw: String(value), format: .integer)
    }

    private static func miles(_ value: Double) -> XlsxCell {
        .number(raw: plain(value, digits: 0), format: .integer)
    }

    private static func rpmCell(_ value: Double) -> XlsxCell {
        .number(raw: plain(value), format: .decimal2)
    }

    private static func gallons(_ value: Double?) -> XlsxCell {
        guard let value else { return .blank }
        return .number(raw: plain(value), format: .decimal2)
    }

    private static func unitPriceCell(_ dollars: Double?) -> XlsxCell {
        let raw = unitPrice(dollars)
        guard !raw.isEmpty else { return .blank }
        return .number(raw: raw, format: .decimal3)
    }

    /// `nil` and non-finite prices are an empty cell. Zero is the numeric value `0.000`.
    private static func unitPrice(_ dollars: Double?) -> String {
        guard let dollars, dollars.isFinite else { return "" }
        return UnitPricePlain.formatPlain(thousandths: UnitPricePlain.thousandths(from: dollars))
    }

    private static func plain(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), arguments: [value])
    }
}

/// Three-decimal per-gallon price, matching Android `UnitPrice`.
enum UnitPricePlain {
    static func thousandths(from value: Double) -> Int64 {
        guard value.isFinite else { return 0 }
        let sign: Int64 = value < 0 ? -1 : 1
        let scaled = abs(value) * 1000
        return sign * Int64((scaled + 1e-8).rounded(.toNearestOrAwayFromZero))
    }

    static func formatPlain(thousandths: Int64) -> String {
        let negative = thousandths < 0
        let absolute = abs(thousandths)
        let dollars = absolute / 1000
        let fraction = String(format: "%03d", absolute % 1000)
        return "\(negative ? "-" : "")\(dollars).\(fraction)"
    }

    /// Gallons times a per-gallon price in thousandths, half-up to cents.
    static func timesGallons(thousandths: Int64, gallons: Double) -> MoneyCents {
        if gallons <= 0 || thousandths == 0 { return .zero }
        let gallonHundredths = Int64((gallons * 100).rounded(.toNearestOrAwayFromZero))
        if gallonHundredths <= 0 { return .zero }
        let negative = thousandths < 0
        let product = abs(thousandths) * gallonHundredths
        let cents = (product + 500) / 1000
        return MoneyCents(cents: negative ? -cents : cents)
    }
}
