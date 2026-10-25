import XCTest
@testable import TruckoRigDomain

/// Generates an accountant workbook and checks sheets, headers and values by unzipping the
/// `.xlsx` package and parsing the worksheet XML.
final class AccountantWorkbookTests: XCTestCase {

    func testAllSectionsUnzipToSheetsHeadersAndValues() throws {
        let files = try unzip(AccountantWorkbook.data(input: sampleInput(), sections: [.all]))
        let names = try sheetNames(in: files)
        XCTAssertEqual(names, ["Сводка", "Грузы", "Дизель", "Суточные", "ТО"])

        let summary = try rows(named: "Сводка", names: names, files: files)
        XCTAssertEqual(summary[0], ["TruckoRig — отчёт для бухгалтера", ""])
        XCTAssertEqual(summary[1], ["Год", "2026"])
        XCTAssertEqual(summary[2], ["Валовой доход (paycheck), USD", "50000.00"])
        XCTAssertTrue(summary.contains(["Грузов", "2"]))
        XCTAssertTrue(summary.contains(["Сумма ставок грузов, USD", "3500.00"]))
        XCTAssertTrue(summary.contains(["Заправок дизеля", "1"]))
        XCTAssertTrue(summary.contains(["Дизель всего, USD", "120.50"]))
        XCTAssertTrue(summary.contains(["Дней на рейсах (суточные)", "2"]))
        XCTAssertTrue(summary.contains(["Ставка суточных, USD/день", "69.00"]))
        XCTAssertTrue(summary.contains(["Суточные всего, USD", "138.00"]))
        XCTAssertTrue(summary.contains(["Записей ТО", "1"]))
        XCTAssertTrue(summary.contains(["ТО всего, USD", "350.00"]))
        XCTAssertEqual(summary.last?.first, "Подсказка")

        let loads = try rows(named: "Грузы", names: names, files: files)
        XCTAssertEqual(
            loads[0],
            ["Дата", "Trip ID", "Маршрут", "Ставка, USD", "Мили", "RPM", "Дней на рейсе"]
        )
        XCTAssertEqual(loads[1], ["46143", "T-90", "C → D", "1000.00", "400", "2.50", "2"])
        XCTAssertEqual(loads[2], ["46174", "T-100", "A → B", "2500.00", "500", "5.00", "1"])

        let diesel = try rows(named: "Дизель", names: names, files: files)
        XCTAssertEqual(
            diesel[0],
            ["Неделя", "Год", "Начало недели", "Конец недели", "Сумма, USD", "Галлоны", "Цена / гал", "Цена со скидкой / гал", "Экономия, USD", "Место"]
        )
        XCTAssertEqual(
            diesel[1],
            ["22", "2026", "46167", "46173", "120.50", "40.00", "3.500", "", "", "Pilot"]
        )

        let perDiem = try rows(named: "Суточные", names: names, files: files)
        XCTAssertEqual(perDiem[0], ["Дата на рейсе", "Ставка, USD", "Сумма, USD"])
        XCTAssertEqual(perDiem[1], ["46174", "69.00", "69.00"])
        XCTAssertEqual(perDiem[2], ["46175", "69.00", "69.00"])
        XCTAssertEqual(perDiem[3], ["ИТОГО (2 дн.)", "69.00", "138.00"])

        let maintenance = try rows(named: "ТО", names: names, files: files)
        XCTAssertEqual(maintenance[0], ["Дата ТО", "Услуга", "Описание", "Сумма, USD"])
        XCTAssertEqual(maintenance[1], ["46091", "Oil change", "Full service", "350.00"])
        XCTAssertEqual(maintenance[2], ["ИТОГО", "", "", "350.00"])

        let styles = try text(files, "xl/styles.xml")
        XCTAssertTrue(styles.contains("#,##0.00"))
        XCTAssertTrue(styles.contains("FFE6EDE9"))
        XCTAssertTrue(styles.contains("<cellStyleXfs"))
        XCTAssertTrue(styles.contains("<cellStyles"))
        XCTAssertTrue(styles.contains("name=\"Normal\""))
        let loadsXML = try text(files, try path(named: "Грузы", names: names, files: files))
        XCTAssertTrue(loadsXML.contains("t=\"inlineStr\" s=\"1\""))
        XCTAssertTrue(loadsXML.contains("<v>46143</v>"))
        XCTAssertTrue(loadsXML.contains("ySplit=\"1\""))
        XCTAssertTrue(loadsXML.contains("<cols>"))
        let summaryXML = try text(files, try path(named: "Сводка", names: names, files: files))
        XCTAssertFalse(summaryXML.contains("s=\"1\""))
        XCTAssertFalse(summaryXML.contains("ySplit"))
        XCTAssertTrue(summaryXML.contains("<v>50000.00</v>"))
        XCTAssertFalse(summaryXML.contains("t=\"inlineStr\"><is><t>50000.00"))
    }

    func testFrenchCaptionsKeepColumnsValuesAndFileName() throws {
        let russian = try unzip(AccountantWorkbook.data(input: sampleInput(), sections: [.all]))
        let french = try unzip(AccountantWorkbook.data(input: sampleInput(), sections: [.all], language: .french))
        let russianNames = try sheetNames(in: russian)
        let frenchNames = try sheetNames(in: french)
        XCTAssertEqual(russianNames, ["Сводка", "Грузы", "Дизель", "Суточные", "ТО"])
        XCTAssertEqual(frenchNames, ["Sommaire", "Voyages", "Diesel", "Indemnité", "Entretien"])

        let russianLoads = try rows(named: "Грузы", names: russianNames, files: russian)
        let frenchLoads = try rows(named: "Voyages", names: frenchNames, files: french)
        XCTAssertEqual(
            frenchLoads[0],
            ["Date", "Trip ID", "Trajet", "Taux, USD", "Milles", "RPM", "Jours en voyage"]
        )
        XCTAssertEqual(frenchLoads[0].count, russianLoads[0].count)
        XCTAssertEqual(Array(frenchLoads.dropFirst()), Array(russianLoads.dropFirst()))

        let russianDiesel = try rows(named: "Дизель", names: russianNames, files: russian)
        let frenchDiesel = try rows(named: "Diesel", names: frenchNames, files: french)
        XCTAssertEqual(frenchDiesel[0].count, russianDiesel[0].count)
        XCTAssertEqual(frenchDiesel[0][2], "Début de la semaine")
        XCTAssertEqual(frenchDiesel[0][3], "Fin de la semaine")
        XCTAssertEqual(Array(frenchDiesel.dropFirst()), Array(russianDiesel.dropFirst()))

        let russianPerDiem = try rows(named: "Суточные", names: russianNames, files: russian)
        let frenchPerDiem = try rows(named: "Indemnité", names: frenchNames, files: french)
        XCTAssertEqual(frenchPerDiem[0], ["Date en voyage", "Taux, USD", "Montant, USD"])
        XCTAssertEqual(frenchPerDiem[0].count, russianPerDiem[0].count)
        XCTAssertEqual(Array(frenchPerDiem.dropFirst().dropLast()), Array(russianPerDiem.dropFirst().dropLast()))
        XCTAssertEqual(frenchPerDiem.last, ["TOTAL (2 jours)", "69.00", "138.00"])
        XCTAssertEqual(russianPerDiem.last, ["ИТОГО (2 дн.)", "69.00", "138.00"])

        let russianMaintenance = try rows(named: "ТО", names: russianNames, files: russian)
        let frenchMaintenance = try rows(named: "Entretien", names: frenchNames, files: french)
        XCTAssertEqual(frenchMaintenance[0], ["Date d'entretien", "Service", "Description", "Montant, USD"])
        XCTAssertEqual(frenchMaintenance[0].count, russianMaintenance[0].count)
        XCTAssertEqual(frenchMaintenance[1], russianMaintenance[1])
        XCTAssertEqual(frenchMaintenance.last, ["TOTAL", "", "", "350.00"])
        XCTAssertEqual(russianMaintenance.last, ["ИТОГО", "", "", "350.00"])

        XCTAssertEqual(AccountantWorkbook.fileLabel([.all]), "All")
        XCTAssertEqual(AccountantWorkbook.fileLabel([.loads]), "Loads")
        XCTAssertEqual(AccountantWorkbook.fileLabel([.diesel]), "Diesel")
        XCTAssertEqual(AccountantWorkbook.fileLabel([.perDiem]), "PerDiem")
        XCTAssertEqual(AccountantWorkbook.fileLabel([.maintenance]), "Maintenance")
    }

    func testKilometerCaptionsConvertNumbersAndKeepSheetShape() throws {
        let miles = try unzip(AccountantWorkbook.data(input: sampleInput(), sections: [.all]))
        let kilometers = try unzip(
            AccountantWorkbook.data(input: sampleInput(), sections: [.all], units: .kilometers)
        )
        let french = try unzip(
            AccountantWorkbook.data(input: sampleInput(), sections: [.all], language: .french, units: .kilometers)
        )
        let mileNames = try sheetNames(in: miles)
        let kilometerNames = try sheetNames(in: kilometers)
        let frenchNames = try sheetNames(in: french)
        XCTAssertEqual(kilometerNames, mileNames)
        XCTAssertEqual(frenchNames, ["Sommaire", "Voyages", "Diesel", "Indemnité", "Entretien"])

        let mileLoads = try rows(named: "Грузы", names: mileNames, files: miles)
        let kilometerLoads = try rows(named: "Грузы", names: kilometerNames, files: kilometers)
        XCTAssertEqual(kilometerLoads[0].count, mileLoads[0].count)
        XCTAssertEqual(
            kilometerLoads[0],
            ["Дата", "Trip ID", "Маршрут", "Ставка, USD", "Километры", "$/км", "Дней на рейсе"]
        )
        XCTAssertEqual(kilometerLoads[1][3], "1000.00")
        XCTAssertEqual(kilometerLoads[1][4], plain(400 * 1.609344))
        XCTAssertEqual(kilometerLoads[1][5], plain(2.50 / 1.609344))
        XCTAssertEqual(kilometerLoads[2][3], "2500.00")
        XCTAssertEqual(kilometerLoads[2][4], plain(500 * 1.609344))
        XCTAssertEqual(mileLoads[1][4], "400")

        let kilometerDiesel = try rows(named: "Дизель", names: kilometerNames, files: kilometers)
        XCTAssertEqual(kilometerDiesel[0].count, 10)
        XCTAssertEqual(
            kilometerDiesel[0],
            ["Неделя", "Год", "Начало недели", "Конец недели", "Сумма, USD", "Литры", "Цена / л", "Цена со скидкой / л", "Экономия, USD", "Место"]
        )
        XCTAssertEqual(kilometerDiesel[1][4], "120.50")
        XCTAssertEqual(kilometerDiesel[1][5], plain(40 * 3.785411784))
        XCTAssertEqual(kilometerDiesel[1][6], pricePerLiter(3.5))

        let frenchLoads = try rows(named: "Voyages", names: frenchNames, files: french)
        XCTAssertEqual(frenchLoads[0].count, kilometerLoads[0].count)
        XCTAssertEqual(frenchLoads[0][4], "Kilomètres")
        XCTAssertEqual(frenchLoads[0][5], "$/km")
        XCTAssertEqual(Array(frenchLoads.dropFirst()), Array(kilometerLoads.dropFirst()))
        let frenchDiesel = try rows(named: "Diesel", names: frenchNames, files: french)
        XCTAssertEqual(frenchDiesel[0][5], "Litres")
        XCTAssertEqual(frenchDiesel[0][6], "Prix / L")
        XCTAssertEqual(frenchDiesel[0][7], "Prix avec rabais / L")
        XCTAssertEqual(Array(frenchDiesel.dropFirst()), Array(kilometerDiesel.dropFirst()))

        let typed = try typedRows(named: "Грузы", names: kilometerNames, files: kilometers)
        XCTAssertEqual(typed[1][4].kind, .number)
        XCTAssertEqual(typed[1][3].kind, .number)
    }

    func testNumericCellsDatesStylesAndTotals() throws {
        XCTAssertEqual(XlsxWorkbook.excelSerial(iso: "2026-03-02"), 46083)
        XCTAssertEqual(XlsxWorkbook.excelSerial(iso: "1900-03-01"), 61)
        XCTAssertEqual(XlsxWorkbook.excelSerial(iso: "1900-01-01"), 1)
        XCTAssertNil(XlsxWorkbook.excelSerial(iso: "2026-02-31"))
        XCTAssertNil(XlsxWorkbook.excelSerial(iso: "03-02-2026"))

        var input = sampleInput()
        input.maintenance[0].serviceDate = "2026-03-02"
        let files = try unzip(AccountantWorkbook.data(input: input, sections: [.all]))
        let names = try sheetNames(in: files)
        let formats = try formatCodes(try text(files, "xl/styles.xml"))
        XCTAssertEqual(formats[0], "General")
        XCTAssertTrue(formats.values.contains("#,##0.00"))
        XCTAssertTrue(formats.values.contains("0"))
        XCTAssertTrue(formats.values.contains("0.00"))
        XCTAssertTrue(formats.values.contains("0.000"))
        XCTAssertTrue(formats.values.contains("yyyy-mm-dd"))

        let summary = try typedRows(named: "Сводка", names: names, files: files)
        assertText(summary[1][0], "Год")
        assertNumber(summary[1][1], value: "2026", format: "0", formats: formats)
        assertNumber(summary[2][1], value: "50000.00", format: "#,##0.00", formats: formats)
        let loadTotal = try XCTUnwrap(summary.first { $0.first?.value == "Сумма ставок грузов, USD" })
        assertNumber(loadTotal[1], value: "3500.00", format: "#,##0.00", formats: formats)
        let perDiemTotalSummary = try XCTUnwrap(summary.first { $0.first?.value == "Суточные всего, USD" })
        assertNumber(perDiemTotalSummary[1], value: "138.00", format: "#,##0.00", formats: formats)

        let loads = try typedRows(named: "Грузы", names: names, files: files)
        XCTAssertTrue(loads[0].allSatisfy { $0.kind == .text })
        assertNumber(loads[1][0], value: "46143", format: "yyyy-mm-dd", formats: formats)
        assertText(loads[1][1], "T-90")
        assertText(loads[1][2], "C → D")
        assertNumber(loads[1][3], value: "1000.00", format: "#,##0.00", formats: formats)
        assertNumber(loads[1][4], value: "400", format: "0", formats: formats)
        assertNumber(loads[1][5], value: "2.50", format: "0.00", formats: formats)
        assertNumber(loads[1][6], value: "2", format: "0", formats: formats)
        assertNumber(loads[2][3], value: "2500.00", format: "#,##0.00", formats: formats)

        let diesel = try typedRows(named: "Дизель", names: names, files: files)
        assertNumber(diesel[1][0], value: "22", format: "0", formats: formats)
        assertNumber(diesel[1][1], value: "2026", format: "0", formats: formats)
        assertNumber(diesel[1][2], value: "46167", format: "yyyy-mm-dd", formats: formats)
        assertNumber(diesel[1][3], value: "46173", format: "yyyy-mm-dd", formats: formats)
        assertNumber(diesel[1][4], value: "120.50", format: "#,##0.00", formats: formats)
        assertNumber(diesel[1][5], value: "40.00", format: "0.00", formats: formats)
        assertNumber(diesel[1][6], value: "3.500", format: "0.000", formats: formats)
        XCTAssertEqual(diesel[1][7].kind, .blank)
        XCTAssertEqual(diesel[1][8].kind, .blank)
        assertText(diesel[1][9], "Pilot")

        let perDiem = try typedRows(named: "Суточные", names: names, files: files)
        assertNumber(perDiem[1][0], value: "46174", format: "yyyy-mm-dd", formats: formats)
        assertNumber(perDiem[1][1], value: "69.00", format: "#,##0.00", formats: formats)
        let perDiemTotal = perDiem[3]
        assertText(perDiemTotal[0], "ИТОГО (2 дн.)")
        assertNumber(perDiemTotal[1], value: "69.00", format: "#,##0.00", formats: formats)
        assertNumber(perDiemTotal[2], value: "138.00", format: "#,##0.00", formats: formats)

        let maintenance = try typedRows(named: "ТО", names: names, files: files)
        assertNumber(maintenance[1][0], value: "46083", format: "yyyy-mm-dd", formats: formats)
        assertText(maintenance[1][1], "Oil change")
        assertNumber(maintenance[1][3], value: "350.00", format: "#,##0.00", formats: formats)
        assertText(maintenance[2][0], "ИТОГО")
        XCTAssertEqual(maintenance[2][1].kind, .blank)
        XCTAssertEqual(maintenance[2][2].kind, .blank)
        assertNumber(maintenance[2][3], value: "350.00", format: "#,##0.00", formats: formats)

        for name in ["Сводка", "Грузы", "Дизель", "Суточные", "ТО"] {
            let rows = try typedRows(named: name, names: names, files: files)
            for row in rows {
                for cell in row where cell.kind == .number {
                    XCTAssertNotEqual(formats[cell.style], "General", "\(name) numeric cell \(cell.value) has no numFmt")
                    XCTAssertFalse(cell.value.contains(","), "localized decimal in \(name): \(cell.value)")
                }
                for cell in row where cell.kind == .text {
                    let format = formats[cell.style] ?? "General"
                    XCTAssertEqual(format, "General", "text cell \(cell.value) on \(name) uses \(format)")
                }
            }
        }

        let loadsXML = try text(files, try path(named: "Грузы", names: names, files: files))
        XCTAssertFalse(loadsXML.contains("t=\"inlineStr\"><is><t>2500.00"))
        XCTAssertTrue(loadsXML.contains("<v>2500.00</v>"))
        let maintenanceXML = try text(files, try path(named: "ТО", names: names, files: files))
        XCTAssertFalse(maintenanceXML.contains(">2026-03-02<"))
        XCTAssertTrue(maintenanceXML.contains("<v>46083</v>"))
        XCTAssertFalse(maintenanceXML.contains("t=\"inlineStr\"><is><t>350.00"))
    }

    /// Matches Android `AccountantWorkbookBuilderTest` empty-vs-zero: missing values are empty
    /// cells, and a real zero stays a number. Week, year, and day counters use format `0`.
    func testBlankStaysEmptyAndRealZeroStaysNumeric() throws {
        XCTAssertEqual(XlsxCell.date(iso: ""), .blank)
        XCTAssertEqual(XlsxCell.date(iso: "   "), .blank)
        XCTAssertEqual(XlsxCell.date(iso: "not-a-date"), .text("not-a-date"))

        let input = AccountantWorkbookInput(
            year: 2026,
            loads: [
                AccountantWorkbookLoad(
                    date: "2026-06-01",
                    tripId: "100",
                    route: "A → B",
                    rate: MoneyCents.fromDollars(100),
                    miles: 0,
                    onDutyDays: 0
                ),
            ],
            diesel: [
                AccountantWorkbookDiesel(
                    weekNumber: 22,
                    year: 2026,
                    weekStartDate: "",
                    weekEndDate: "   ",
                    totalAmount: MoneyCents.fromDollars(10),
                    gallons: nil,
                    pricePerGallon: nil,
                    discountPricePerGallon: nil,
                    location: ""
                ),
                AccountantWorkbookDiesel(
                    weekNumber: 23,
                    year: 2026,
                    weekStartDate: "2026-06-01",
                    weekEndDate: "2026-06-07",
                    totalAmount: .zero,
                    gallons: 0,
                    pricePerGallon: 0,
                    discountPricePerGallon: nil,
                    location: "Pilot"
                ),
                AccountantWorkbookDiesel(
                    weekNumber: 24,
                    year: 2026,
                    weekStartDate: "2026-06-08",
                    weekEndDate: "2026-06-14",
                    totalAmount: MoneyCents.fromDollars(40),
                    gallons: 10,
                    pricePerGallon: 4,
                    discountPricePerGallon: 4,
                    location: "TA"
                ),
            ],
            perDiemDates: [],
            maintenance: [],
            grossIncome: 0
        )
        let files = try unzip(AccountantWorkbook.data(input: input, sections: [.all]))
        let names = try sheetNames(in: files)
        let formats = try formatCodes(try text(files, "xl/styles.xml"))
        XCTAssertTrue(formats.values.contains("yyyy-mm-dd"))
        XCTAssertFalse(formats.values.contains("dd.mm.yyyy"))

        let loads = try typedRows(named: "Грузы", names: names, files: files)
        assertText(loads[1][1], "100")
        assertText(loads[1][2], "A → B")
        assertNumber(loads[1][0], value: "46174", format: "yyyy-mm-dd", formats: formats)
        assertNumber(loads[1][4], value: "0", format: "0", formats: formats)
        assertNumber(loads[1][5], value: "0.00", format: "0.00", formats: formats)
        assertNumber(loads[1][6], value: "0", format: "0", formats: formats)

        let diesel = try typedRows(named: "Дизель", names: names, files: files)
        let missing = diesel[1]
        assertNumber(missing[0], value: "22", format: "0", formats: formats)
        assertNumber(missing[1], value: "2026", format: "0", formats: formats)
        XCTAssertEqual(missing[2].kind, .blank)
        XCTAssertEqual(missing[3].kind, .blank)
        assertNumber(missing[4], value: "10.00", format: "#,##0.00", formats: formats)
        XCTAssertEqual(missing[5].kind, .blank)
        XCTAssertEqual(missing[6].kind, .blank)
        XCTAssertEqual(missing[7].kind, .blank)
        XCTAssertEqual(missing[8].kind, .blank)
        XCTAssertEqual(missing[9].kind, .blank)
        XCTAssertFalse(missing.contains { $0.kind == .number && $0.value == "0" && formats[$0.style] != "0" })

        let presentZero = diesel[2]
        assertNumber(presentZero[5], value: "0.00", format: "0.00", formats: formats)
        assertNumber(presentZero[6], value: "0.000", format: "0.000", formats: formats)
        XCTAssertEqual(presentZero[7].kind, .blank)
        XCTAssertEqual(presentZero[8].kind, .blank)
        assertNumber(presentZero[4], value: "0.00", format: "#,##0.00", formats: formats)
        assertText(presentZero[9], "Pilot")

        let equalPrices = diesel[3]
        assertNumber(equalPrices[6], value: "4.000", format: "0.000", formats: formats)
        assertNumber(equalPrices[7], value: "4.000", format: "0.000", formats: formats)
        assertNumber(equalPrices[8], value: "0.00", format: "#,##0.00", formats: formats)
        assertText(equalPrices[9], "TA")

        let perDiem = try typedRows(named: "Суточные", names: names, files: files)
        XCTAssertEqual(perDiem.count, 2)
        assertText(perDiem[1][0], "ИТОГО (0 дн.)")
        assertNumber(perDiem[1][1], value: "69.00", format: "#,##0.00", formats: formats)
        assertNumber(perDiem[1][2], value: "0.00", format: "#,##0.00", formats: formats)

        let maintenance = try typedRows(named: "ТО", names: names, files: files)
        XCTAssertEqual(maintenance.count, 2)
        assertText(maintenance[1][0], "ИТОГО")
        XCTAssertEqual(maintenance[1][1].kind, .blank)
        XCTAssertEqual(maintenance[1][2].kind, .blank)
        assertNumber(maintenance[1][3], value: "0.00", format: "#,##0.00", formats: formats)

        let summary = try typedRows(named: "Сводка", names: names, files: files)
        assertNumber(summary[1][1], value: "2026", format: "0", formats: formats)
        assertNumber(summary[2][1], value: "0.00", format: "#,##0.00", formats: formats)

        let dieselXML = try text(files, try path(named: "Дизель", names: names, files: files))
        XCTAssertFalse(dieselXML.contains(">2026-06-01<"))
        XCTAssertFalse(dieselXML.contains("<v></v>"))
        XCTAssertTrue(dieselXML.contains("<v>0.000</v>"))
        XCTAssertTrue(dieselXML.contains("<v>0.00</v>"))
    }

    func testDieselOnlyOmitsOtherDataSheets() throws {
        let files = try unzip(AccountantWorkbook.data(input: sampleInput(), sections: [.diesel]))
        let names = try sheetNames(in: files)
        XCTAssertEqual(names, ["Сводка", "Дизель"])
        let summary = try rows(named: "Сводка", names: names, files: files)
        XCTAssertTrue(summary.contains(["Дизель всего, USD", "120.50"]))
        XCTAssertFalse(summary.contains { $0.first == "Грузов" })
        XCTAssertFalse(summary.contains { $0.first == "Суточные всего, USD" })
        let diesel = try rows(named: "Дизель", names: names, files: files)
        XCTAssertEqual(diesel[1][4], "120.50")
    }

    func testEscapeAndFileNameAndSavings() throws {
        var input = sampleInput()
        input.loads[0].route = "A & B <C> \"q\""
        input.diesel[0].discountPricePerGallon = 3.012
        let files = try unzip(AccountantWorkbook.data(input: input, sections: [.loads, .diesel]))
        let names = try sheetNames(in: files)
        let loads = try rows(named: "Грузы", names: names, files: files)
        XCTAssertEqual(loads.first { $0.count > 2 && $0[1] == "T-100" }?[2], "A & B <C> \"q\"")
        let raw = try text(files, try path(named: "Грузы", names: names, files: files))
        XCTAssertTrue(raw.contains("&amp;"))
        XCTAssertTrue(raw.contains("&lt;"))
        XCTAssertTrue(raw.contains("&quot;"))

        let diesel = try rows(named: "Дизель", names: names, files: files)
        XCTAssertEqual(diesel[1][7], "3.012")
        // 40 gal * (3.500 - 3.012) = 40 * 0.488 = 19.52, integer thousandths path.
        XCTAssertEqual(diesel[1][8], "19.52")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        XCTAssertEqual(
            AccountantWorkbook.fileName(year: 2026, sections: [.all], day: day, calendar: calendar),
            "TruckoRig_Tax_2026_All_20261022.xlsx"
        )
        XCTAssertEqual(
            AccountantWorkbook.fileName(year: 2026, sections: [.diesel], day: day, calendar: calendar),
            "TruckoRig_Tax_2026_Diesel_20261022.xlsx"
        )
        XCTAssertEqual(AccountantWorkbook.fileLabel([.loads, .diesel]), "Custom")
        XCTAssertEqual(AccountantWorkbook.fileLabel([]), "All")
        XCTAssertEqual(AccountantWorkbook.fileLabel([.perDiem]), "PerDiem")
        XCTAssertEqual(AccountantWorkbook.fileLabel([.maintenance]), "Maintenance")
        XCTAssertTrue(AccountantWorkbook.isEmpty(
            AccountantWorkbookInput(year: 2026, loads: [], diesel: [], perDiemDates: [], maintenance: [], grossIncome: 0),
            sections: [.all]
        ))
    }

    private func sampleInput() -> AccountantWorkbookInput {
        AccountantWorkbookInput(
            year: 2026,
            loads: [
                AccountantWorkbookLoad(
                    date: "2026-06-01",
                    tripId: "T-100",
                    route: "A → B",
                    rate: MoneyCents.fromDollars(2500),
                    miles: 500,
                    onDutyDays: 1
                ),
                AccountantWorkbookLoad(
                    date: "2026-05-01",
                    tripId: "T-90",
                    route: "C → D",
                    rate: MoneyCents.fromDollars(1000),
                    miles: 400,
                    onDutyDays: 2
                ),
            ],
            diesel: [
                AccountantWorkbookDiesel(
                    weekNumber: 22,
                    year: 2026,
                    weekStartDate: "2026-05-25",
                    weekEndDate: "2026-05-31",
                    totalAmount: MoneyCents.fromDollars(120.5),
                    gallons: 40,
                    pricePerGallon: 3.5,
                    discountPricePerGallon: nil,
                    location: "Pilot"
                ),
            ],
            perDiemDates: ["2026-06-02", "2026-06-01"],
            maintenance: [
                AccountantWorkbookMaintenance(
                    serviceDate: "2026-03-10",
                    serviceName: "Oil change",
                    description: "Full service",
                    amount: MoneyCents.fromDollars(350)
                ),
            ],
            grossIncome: 50_000
        )
    }

    private func plain(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func pricePerLiter(_ perGallon: Double) -> String {
        let perLiter = perGallon / 3.785411784
        return UnitPricePlain.formatPlain(thousandths: UnitPricePlain.thousandths(from: perLiter))
    }

    private func unzip(_ data: Data) throws -> [String: Data] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xlsx-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("book.xlsx")
        try data.write(to: archive)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let unzip = unzipExecutable()
        let process = Process()
        process.executableURL = unzip
        process.arguments = ["-o", "-qq", archive.path, "-d", destination.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let errorText = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            XCTFail("unzip failed: \(errorText)")
            return [:]
        }
        var files: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            let relative = url.path.replacingOccurrences(of: destination.path + "/", with: "")
            files[relative] = try Data(contentsOf: url)
        }
        XCTAssertNotNil(files["[Content_Types].xml"])
        XCTAssertNotNil(files["xl/workbook.xml"])
        return files
    }

    private func unzipExecutable() -> URL {
        let candidates = ["/usr/bin/unzip", "/bin/unzip"]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/unzip")
    }

    private func sheetNames(in files: [String: Data]) throws -> [String] {
        let workbook = try text(files, "xl/workbook.xml")
        let rels = try text(files, "xl/_rels/workbook.xml.rels")
        let pattern = #"<sheet name="([^"]+)" sheetId="\d+" r:id="(rId\d+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(workbook.startIndex..., in: workbook)
        return regex.matches(in: workbook, range: range).map { match in
            let name = String(workbook[Range(match.range(at: 1), in: workbook)!])
            let id = String(workbook[Range(match.range(at: 2), in: workbook)!])
            XCTAssertTrue(rels.contains("Id=\"\(id)\""))
            return name
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
        }
    }

    private func path(named name: String, names: [String], files: [String: Data]) throws -> String {
        guard let index = names.firstIndex(of: name) else {
            XCTFail("missing sheet \(name)")
            return ""
        }
        return "xl/worksheets/sheet\(index + 1).xml"
    }

    private func rows(named name: String, names: [String], files: [String: Data]) throws -> [[String]] {
        try typedRows(named: name, names: names, files: files).map { $0.map(\.value) }
    }

    private func typedRows(named name: String, names: [String], files: [String: Data]) throws -> [[SheetCell]] {
        let xml = try text(files, try path(named: name, names: names, files: files))
        return SheetXML.typedRows(in: xml)
    }

    /// Style index → format code, using `General` for built-in numFmtId 0.
    private func formatCodes(_ styles: String) throws -> [Int: String] {
        var codes: [Int: String] = [0: "General"]
        let numRegex = try NSRegularExpression(pattern: #"<numFmt numFmtId="(\d+)" formatCode="([^"]*)"/>"#)
        let full = NSRange(styles.startIndex..., in: styles)
        for match in numRegex.matches(in: styles, range: full) {
            let id = Int(styles[Range(match.range(at: 1), in: styles)!]) ?? -1
            codes[id] = String(styles[Range(match.range(at: 2), in: styles)!])
        }
        guard let start = styles.range(of: "<cellXfs"),
              let end = styles.range(of: "</cellXfs>") else {
            XCTFail("missing cellXfs")
            return [:]
        }
        let block = String(styles[start.lowerBound..<end.lowerBound])
        let xfRegex = try NSRegularExpression(pattern: #"<xf numFmtId="(\d+)""#)
        let blockRange = NSRange(block.startIndex..., in: block)
        var map: [Int: String] = [:]
        for (index, match) in xfRegex.matches(in: block, range: blockRange).enumerated() {
            let id = Int(block[Range(match.range(at: 1), in: block)!]) ?? -1
            map[index] = codes[id] ?? "missing"
        }
        return map
    }

    private func assertNumber(
        _ cell: SheetCell,
        value: String,
        format: String,
        formats: [Int: String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(cell.kind, .number, "expected number \(value)", file: file, line: line)
        XCTAssertEqual(cell.value, value, file: file, line: line)
        XCTAssertEqual(formats[cell.style], format, "style \(cell.style) for \(value)", file: file, line: line)
    }

    private func assertText(
        _ cell: SheetCell,
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(cell.kind, .text, file: file, line: line)
        XCTAssertEqual(cell.value, value, file: file, line: line)
    }

    private func text(_ files: [String: Data], _ path: String) throws -> String {
        guard let data = files[path], let text = String(data: data, encoding: .utf8) else {
            XCTFail("missing \(path)")
            return ""
        }
        return text
    }
}

private struct SheetCell: Equatable {
    enum Kind: Equatable {
        case blank
        case text
        case number
    }

    var kind: Kind
    var style: Int
    var value: String
}

/// Reads worksheet cells by reference so blank cells keep their columns.
/// Numeric cells contribute the raw `<v>` text. Inline strings are unescaped.
private enum SheetXML {
    static func typedRows(in xml: String) -> [[SheetCell]] {
        var rows: [[SheetCell]] = []
        var search = xml[...]
        while let rowStart = search.range(of: "<row") {
            let after = search[rowStart.upperBound...]
            guard let rowEnd = after.range(of: "</row>") else { break }
            rows.append(parseRow(String(after[..<rowEnd.lowerBound])))
            search = after[rowEnd.upperBound...]
        }
        return rows
    }

    private static func parseRow(_ body: String) -> [SheetCell] {
        var parsed: [(column: Int, cell: SheetCell)] = []
        var rest = body[...]
        while let cellStart = rest.range(of: "<c ") {
            let after = rest[cellStart.upperBound...]
            guard let tagEnd = after.firstIndex(of: ">") else { break }
            let tag = after[..<tagEnd]
            let selfClosing = tag.hasSuffix("/")
            let attrs = String(tag)
            let column = columnIndex(in: attrs)
            let style = styleIndex(in: attrs)
            let inline = attrs.contains("t=\"inlineStr\"")
            if selfClosing {
                parsed.append((column, SheetCell(kind: .blank, style: style, value: "")))
                rest = after[after.index(after: tagEnd)...]
                continue
            }
            let bodyStart = after.index(after: tagEnd)
            guard let close = after.range(of: "</c>") else { break }
            let inner = String(after[bodyStart..<close.lowerBound])
            if inline {
                parsed.append((column, SheetCell(kind: .text, style: style, value: unescape(textValue(inner)))))
            } else if let number = element(inner, name: "v") {
                parsed.append((column, SheetCell(kind: .number, style: style, value: number)))
            } else {
                parsed.append((column, SheetCell(kind: .blank, style: style, value: "")))
            }
            rest = after[close.upperBound...]
        }
        let width = parsed.map(\.column).max().map { $0 + 1 } ?? 0
        var row = Array(repeating: SheetCell(kind: .blank, style: 0, value: ""), count: width)
        for entry in parsed where entry.column < width {
            row[entry.column] = entry.cell
        }
        return row
    }

    private static func columnIndex(in attrs: String) -> Int {
        guard let start = attrs.range(of: "r=\""),
              let end = attrs[start.upperBound...].firstIndex(of: "\"") else { return 0 }
        var n = 0
        for scalar in attrs[start.upperBound..<end].unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { break }
            n = n * 26 + Int(scalar.value - 64)
        }
        return max(0, n - 1)
    }

    private static func styleIndex(in attrs: String) -> Int {
        guard let start = attrs.range(of: "s=\""),
              let end = attrs[start.upperBound...].firstIndex(of: "\"") else { return 0 }
        return Int(attrs[start.upperBound..<end]) ?? 0
    }

    private static func textValue(_ body: String) -> String {
        element(body, name: "t") ?? ""
    }

    private static func element(_ body: String, name: String) -> String? {
        guard let open = body.range(of: "<\(name)") else { return nil }
        guard let gt = body[open.upperBound...].firstIndex(of: ">") else { return nil }
        let start = body.index(after: gt)
        guard let close = body.range(of: "</\(name)>") else { return nil }
        return String(body[start..<close.lowerBound])
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
