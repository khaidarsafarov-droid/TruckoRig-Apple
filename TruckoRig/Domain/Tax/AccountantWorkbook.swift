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
/// Captions inside the accountant workbook. `.russian` is the text every existing
/// language already receives. `.french` translates those captions only.
public enum AccountantWorkbookLanguage: Sendable {
    case russian
    case french
}

public struct AccountantWorkbookCopy: Equatable, Sendable {
    public var summaryTitle: String
    public var year: String
    public var grossIncome: String
    public var loadCount: String
    public var loadSum: String
    public var dieselCount: String
    public var dieselSum: String
    public var perDiemDays: String
    public var perDiemRate: String
    public var perDiemSum: String
    public var maintenanceCount: String
    public var maintenanceSum: String
    public var hintLabel: String
    public var hint: String
    public var summarySheet: String
    public var loadsSheet: String
    public var loadsHeader: [String]
    public var dieselSheet: String
    public var dieselHeader: [String]
    public var perDiemSheet: String
    public var perDiemHeader: [String]
    public var maintenanceSheet: String
    public var maintenanceHeader: [String]
    public var total: String
    public var perDiemDayOne: String
    public var perDiemDayOther: String

    public func perDiemTotal(count: Int) -> String {
        let unit = count == 0 || count == 1 ? perDiemDayOne : perDiemDayOther
        return "\(total) (\(count) \(unit))"
    }

    public static let russian = AccountantWorkbookCopy(
        summaryTitle: "TruckoRig — отчёт для бухгалтера",
        year: "Год",
        grossIncome: "Валовой доход (paycheck), USD",
        loadCount: "Грузов",
        loadSum: "Сумма ставок грузов, USD",
        dieselCount: "Заправок дизеля",
        dieselSum: "Дизель всего, USD",
        perDiemDays: "Дней на рейсах (суточные)",
        perDiemRate: "Ставка суточных, USD/день",
        perDiemSum: "Суточные всего, USD",
        maintenanceCount: "Записей ТО",
        maintenanceSum: "ТО всего, USD",
        hintLabel: "Подсказка",
        hint: "Каждый лист — отдельная таблица. Откройте в Excel / Google Таблицах. Отправьте через Telegram, WhatsApp или почту.",
        summarySheet: "Сводка",
        loadsSheet: "Грузы",
        loadsHeader: ["Дата", "Trip ID", "Маршрут", "Ставка, USD", "Мили", "RPM", "Дней на рейсе"],
        dieselSheet: "Дизель",
        dieselHeader: [
            "Неделя", "Год", "Начало недели", "Конец недели", "Сумма, USD",
            "Галлоны", "Цена / гал", "Цена со скидкой / гал", "Экономия, USD", "Место",
        ],
        perDiemSheet: "Суточные",
        perDiemHeader: ["Дата на рейсе", "Ставка, USD", "Сумма, USD"],
        maintenanceSheet: "ТО",
        maintenanceHeader: ["Дата ТО", "Услуга", "Описание", "Сумма, USD"],
        total: "ИТОГО",
        perDiemDayOne: "дн.",
        perDiemDayOther: "дн."
    )

    public static let french = AccountantWorkbookCopy(
        summaryTitle: "TruckoRig — rapport pour le comptable",
        year: "Année",
        grossIncome: "Revenu brut (paie), USD",
        loadCount: "Voyages",
        loadSum: "Somme des taux, USD",
        dieselCount: "Pleins de diesel",
        dieselSum: "Diesel total, USD",
        perDiemDays: "Jours en voyage (indemnité)",
        perDiemRate: "Taux de l'indemnité, USD/jour",
        perDiemSum: "Indemnité totale, USD",
        maintenanceCount: "Entrées d'entretien",
        maintenanceSum: "Entretien total, USD",
        hintLabel: "Note",
        hint: "Chaque feuille est un tableau distinct. Ouvrez-le dans Excel ou Google Sheets. Envoyez-le par Telegram, WhatsApp ou courriel.",
        summarySheet: "Sommaire",
        loadsSheet: "Voyages",
        loadsHeader: ["Date", "Trip ID", "Trajet", "Taux, USD", "Milles", "RPM", "Jours en voyage"],
        dieselSheet: "Diesel",
        dieselHeader: [
            "Semaine", "Année", "Début de la semaine", "Fin de la semaine", "Montant, USD",
            "Gallons", "Prix / gal", "Prix avec rabais / gal", "Économie, USD", "Lieu",
        ],
        perDiemSheet: "Indemnité",
        perDiemHeader: ["Date en voyage", "Taux, USD", "Montant, USD"],
        maintenanceSheet: "Entretien",
        maintenanceHeader: ["Date d'entretien", "Service", "Description", "Montant, USD"],
        total: "TOTAL",
        perDiemDayOne: "jour",
        perDiemDayOther: "jours"
    )

    public static func resolve(_ language: AccountantWorkbookLanguage) -> AccountantWorkbookCopy {
        switch language {
        case .russian: return .russian
        case .french: return .french
        }
    }
}

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
        sections requested: Set<AccountantExportSection>,
        language: AccountantWorkbookLanguage = .russian
    ) -> [XlsxSheet] {
        let sections = resolveSections(requested)
        let copy = AccountantWorkbookCopy.resolve(language)
        var sheets = [summarySheet(input, sections: sections, copy: copy)]
        if sections.contains(.loads) {
            sheets.append(loadsSheet(input, copy: copy))
        }
        if sections.contains(.diesel) {
            sheets.append(dieselSheet(input, copy: copy))
        }
        if sections.contains(.perDiem) {
            sheets.append(perDiemSheet(input, copy: copy))
        }
        if sections.contains(.maintenance) {
            sheets.append(maintenanceSheet(input, copy: copy))
        }
        return sheets
    }

    public static func data(
        input: AccountantWorkbookInput,
        sections: Set<AccountantExportSection>,
        language: AccountantWorkbookLanguage = .russian
    ) -> Data {
        XlsxWorkbook.data(sheets: sheets(input: input, sections: sections, language: language))
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
        sections: Set<AccountantExportSection>,
        copy: AccountantWorkbookCopy
    ) -> XlsxSheet {
        let loadsTotal = input.loads.reduce(MoneyCents.zero) { $0 + $1.rate }
        let dieselTotal = input.diesel.reduce(MoneyCents.zero) { $0 + $1.totalAmount }
        let perDiemDays = input.perDiemDates.count
        let perDiemTotal = PerDiemCalculator.amount(dayCount: perDiemDays)
        let maintenanceTotal = input.maintenance.reduce(MoneyCents.zero) { $0 + $1.amount }
        var rows: [[XlsxCell]] = [
            [.text(copy.summaryTitle), .blank],
            [.text(copy.year), integer(input.year)],
            [.text(copy.grossIncome), money(input.grossIncome)],
            [.blank, .blank],
        ]
        if sections.contains(.loads) {
            rows.append([.text(copy.loadCount), integer(input.loads.count)])
            rows.append([.text(copy.loadSum), money(loadsTotal)])
        }
        if sections.contains(.diesel) {
            rows.append([.text(copy.dieselCount), integer(input.diesel.count)])
            rows.append([.text(copy.dieselSum), money(dieselTotal)])
        }
        if sections.contains(.perDiem) {
            rows.append([.text(copy.perDiemDays), integer(perDiemDays)])
            rows.append([.text(copy.perDiemRate), money(PerDiemCalculator.dailyRate)])
            rows.append([.text(copy.perDiemSum), money(perDiemTotal)])
        }
        if sections.contains(.maintenance) {
            rows.append([.text(copy.maintenanceCount), integer(input.maintenance.count)])
            rows.append([.text(copy.maintenanceSum), money(maintenanceTotal)])
        }
        rows.append([.blank, .blank])
        rows.append([
            .text(copy.hintLabel),
            .text(copy.hint),
        ])
        return XlsxSheet(name: copy.summarySheet, rows: rows, headerRow: false)
    }

    private static func loadsSheet(_ input: AccountantWorkbookInput, copy: AccountantWorkbookCopy) -> XlsxSheet {
        let header = copy.loadsHeader.map {
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
        return XlsxSheet(name: copy.loadsSheet, rows: [header] + body, headerRow: true)
    }

    private static func dieselSheet(_ input: AccountantWorkbookInput, copy: AccountantWorkbookCopy) -> XlsxSheet {
        let header = copy.dieselHeader.map { XlsxCell.text($0) }
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
        return XlsxSheet(name: copy.dieselSheet, rows: [header] + body, headerRow: true)
    }

    private static func perDiemSheet(_ input: AccountantWorkbookInput, copy: AccountantWorkbookCopy) -> XlsxSheet {
        let header = copy.perDiemHeader.map { XlsxCell.text($0) }
        let rate = money(PerDiemCalculator.dailyRate)
        let body = input.perDiemDates.sorted().map { day -> [XlsxCell] in
            [isoDate(day), rate, rate]
        }
        let total = [
            XlsxCell.text(copy.perDiemTotal(count: input.perDiemDates.count)),
            rate,
            money(PerDiemCalculator.amount(dayCount: input.perDiemDates.count)),
        ]
        return XlsxSheet(name: copy.perDiemSheet, rows: [header] + body + [total], headerRow: true)
    }

    private static func maintenanceSheet(_ input: AccountantWorkbookInput, copy: AccountantWorkbookCopy) -> XlsxSheet {
        let header = copy.maintenanceHeader.map { XlsxCell.text($0) }
        let body = input.maintenance.map { entry -> [XlsxCell] in
            [isoDate(entry.serviceDate), .text(entry.serviceName), .text(entry.description), money(entry.amount)]
        }
        let total = input.maintenance.reduce(MoneyCents.zero) { $0 + $1.amount }
        return XlsxSheet(
            name: copy.maintenanceSheet,
            rows: [header] + body + [[.text(copy.total), .blank, .blank, money(total)]],
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
