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
        XCTAssertEqual(loads[1], ["2026-05-01", "T-90", "C → D", "1000.00", "400", "2.50", "2"])
        XCTAssertEqual(loads[2], ["2026-06-01", "T-100", "A → B", "2500.00", "500", "5.00", "1"])

        let diesel = try rows(named: "Дизель", names: names, files: files)
        XCTAssertEqual(
            diesel[0],
            ["Неделя", "Год", "Начало недели", "Конец недели", "Сумма, USD", "Галлоны", "Цена / гал", "Цена со скидкой / гал", "Экономия, USD", "Место"]
        )
        XCTAssertEqual(
            diesel[1],
            ["22", "2026", "2026-05-25", "2026-05-31", "120.50", "40.00", "3.500", "", "", "Pilot"]
        )

        let perDiem = try rows(named: "Суточные", names: names, files: files)
        XCTAssertEqual(perDiem[0], ["Дата на рейсе", "Ставка, USD", "Сумма, USD"])
        XCTAssertEqual(perDiem[1], ["2026-06-01", "69.00", "69.00"])
        XCTAssertEqual(perDiem[2], ["2026-06-02", "69.00", "69.00"])
        XCTAssertEqual(perDiem[3], ["ИТОГО (2 дн.)", "69.00", "138.00"])

        let maintenance = try rows(named: "ТО", names: names, files: files)
        XCTAssertEqual(maintenance[0], ["Дата ТО", "Услуга", "Описание", "Сумма, USD"])
        XCTAssertEqual(maintenance[1], ["2026-03-10", "Oil change", "Full service", "350.00"])
        XCTAssertEqual(maintenance[2], ["ИТОГО", "", "", "350.00"])

        let styles = try text(files, "xl/styles.xml")
        XCTAssertTrue(styles.contains("#,##0.00"))
        XCTAssertTrue(styles.contains("FFE6EDE9"))
        let loadsXML = try text(files, try path(named: "Грузы", names: names, files: files))
        XCTAssertTrue(loadsXML.contains("t=\"inlineStr\" s=\"1\""))
        let summaryXML = try text(files, try path(named: "Сводка", names: names, files: files))
        XCTAssertFalse(summaryXML.contains("s=\"1\""))
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
        let xml = try text(files, try path(named: name, names: names, files: files))
        return SheetXML.rows(in: xml)
    }

    private func text(_ files: [String: Data], _ path: String) throws -> String {
        guard let data = files[path], let text = String(data: data, encoding: .utf8) else {
            XCTFail("missing \(path)")
            return ""
        }
        return text
    }
}

/// Reads inline-string cells out of a worksheet. Entities are decoded in the same order XML uses.
private enum SheetXML {
    static func rows(in xml: String) -> [[String]] {
        xml.components(separatedBy: "</row>").compactMap { part in
            guard part.contains("<row") else { return nil }
            let body = part.components(separatedBy: "<row").last ?? ""
            var cells: [String] = []
            var rest = body[...]
            while let tag = rest.range(of: "<t") {
                let afterTag = rest[tag.upperBound...]
                guard let close = afterTag.firstIndex(of: ">") else { break }
                let content = afterTag[afterTag.index(after: close)...]
                guard let end = content.range(of: "</t>") else { break }
                cells.append(unescape(String(content[..<end.lowerBound])))
                rest = content[end.upperBound...]
            }
            return cells
        }
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
