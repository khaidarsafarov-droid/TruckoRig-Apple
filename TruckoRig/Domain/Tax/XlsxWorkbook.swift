import Foundation

/// Number format applied to a numeric OOXML cell. The raw `<v>` value stays invariant
/// (`.` decimal separator); Excel and Numbers render it with the workbook locale.
public enum XlsxNumberFormat: Equatable, Sendable {
    /// `#,##0.00`
    case money
    /// `0` — miles, week, year, counts.
    case integer
    /// `0.00` — gallons and RPM.
    case decimal2
    /// `0.000` — price per gallon.
    case decimal3
    /// `yyyy-mm-dd`, stored as an Excel 1900 date serial.
    case date
}

/// One cell. Text stays inline strings. Numbers and dates are numeric cells so SUM and
/// sort work, including under a Russian Excel locale.
public enum XlsxCell: Equatable, Sendable {
    case text(String)
    case number(raw: String, format: XlsxNumberFormat)
    case blank

    /// Excel date serial for an ISO `yyyy-mm-dd`, or the original text when it is not a real date.
    public static func date(iso: String) -> XlsxCell {
        guard let serial = XlsxWorkbook.excelSerial(iso: iso) else { return .text(iso) }
        return .number(raw: String(serial), format: .date)
    }
}

/// One worksheet in an OOXML workbook.
public struct XlsxSheet: Equatable, Sendable {
    public var name: String
    public var rows: [[XlsxCell]]
    /// When true, the first row uses the header style (bold, fill `#E6EDE9`) and the pane is frozen.
    public var headerRow: Bool

    public init(name: String, rows: [[XlsxCell]], headerRow: Bool) {
        self.name = name
        self.rows = rows
        self.headerRow = headerRow
    }
}

/// Minimal `.xlsx` writer. The package is a ZIP of OOXML parts with stored (uncompressed)
/// entries, so the app does not need a compression library. Excel, Numbers and `unzip` open it.
public enum XlsxWorkbook {
    public static func data(sheets: [XlsxSheet]) -> Data {
        let safeSheets = sheets.isEmpty
            ? [XlsxSheet(name: "Sheet1", rows: [], headerRow: false)]
            : sheets
        var files: [(String, Data)] = []
        files.append(("[Content_Types].xml", Data(contentTypes(count: safeSheets.count).utf8)))
        files.append(("_rels/.rels", Data(rootRels.utf8)))
        files.append(("xl/workbook.xml", Data(workbookXML(safeSheets).utf8)))
        files.append(("xl/_rels/workbook.xml.rels", Data(workbookRels(count: safeSheets.count).utf8)))
        files.append(("xl/styles.xml", Data(stylesXML.utf8)))
        for (index, sheet) in safeSheets.enumerated() {
            files.append(("xl/worksheets/sheet\(index + 1).xml", Data(worksheetXML(sheet).utf8)))
        }
        return ZipStore.archive(files)
    }

    static func xmlEscape(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            default:
                if scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r" {
                    continue
                }
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }

    static func sheetName(_ name: String) -> String {
        let cleaned = name
            .prefix(31)
            .map { character -> Character in
                switch character {
                case "\\", "/", "*", "?", ":", "[", "]": return "-"
                default: return character
                }
            }
        let text = String(cleaned)
        return text.isEmpty ? "Sheet" : text
    }

    private static func contentTypes(count: Int) -> String {
        var overrides = [
            override("/xl/workbook.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"),
            override("/xl/styles.xml", "application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"),
        ]
        for index in 1...count {
            overrides.append(
                override(
                    "/xl/worksheets/sheet\(index).xml",
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"
                )
            )
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          \(overrides.joined(separator: "\n  "))
        </Types>
        """
    }

    private static func override(_ part: String, _ type: String) -> String {
        "<Override PartName=\"\(part)\" ContentType=\"\(type)\"/>"
    }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static func workbookXML(_ sheets: [XlsxSheet]) -> String {
        let entries = sheets.enumerated().map { index, sheet in
            let name = xmlEscape(sheetName(sheet.name))
            return "<sheet name=\"\(name)\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }.joined(separator: "")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(entries)</sheets></workbook>
        """
    }

    private static func workbookRels(count: Int) -> String {
        var lines: [String] = []
        for index in 1...count {
            lines.append(
                "<Relationship Id=\"rId\(index)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(index).xml\"/>"
            )
        }
        let stylesID = count + 1
        lines.append(
            "<Relationship Id=\"rId\(stylesID)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        )
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          \(lines.joined(separator: "\n  "))
        </Relationships>
        """
    }

    /// Custom format ids start at 164. Built-in ids below that are not repeated here.
    /// Style index 0 is General text, 1 is the header, and the rest follow this list.
    private static let numberFormats: [(XlsxNumberFormat, Int, String)] = [
        (.money, 164, "#,##0.00"),
        (.integer, 165, "0"),
        (.decimal2, 166, "0.00"),
        (.decimal3, 167, "0.000"),
        (.date, 168, "yyyy-mm-dd"),
    ]

    /// Header fill `#E6EDE9`, plus number formats actually referenced by cellXfs.
    /// `cellStyles`/`cellStyleXfs` name the Normal style so Excel, Numbers and openpyxl
    /// do not repair the package or substitute a default stylesheet.
    private static var stylesXML: String {
        let numFmts = numberFormats.map { _, id, code in
            "<numFmt numFmtId=\"\(id)\" formatCode=\"\(code)\"/>"
        }.joined()
        let numericXfs = numberFormats.map { _, id, _ in
            "<xf numFmtId=\"\(id)\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/>"
        }.joined()
        let xfCount = numberFormats.count + 2
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <numFmts count="\(numberFormats.count)">\(numFmts)</numFmts>
          <fonts count="2">
            <font><sz val="11"/><name val="Calibri"/></font>
            <font><b/><sz val="11"/><name val="Calibri"/></font>
          </fonts>
          <fills count="3">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
            <fill><patternFill patternType="solid"><fgColor rgb="FFE6EDE9"/></patternFill></fill>
          </fills>
          <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="\(xfCount)">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
            \(numericXfs)
          </cellXfs>
          <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
          <dxfs count="0"/>
          <tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
        </styleSheet>
        """
    }

    private static func styleIndex(for format: XlsxNumberFormat) -> Int {
        let offset = numberFormats.firstIndex { $0.0 == format } ?? 0
        return offset + 2
    }

    /// Excel 1900 date system. `2026-03-02` is serial 46083.
    /// Dates on or after 1900-03-01 equal the day count since 1899-12-30, which lines up
    /// with Excel once its fictional 1900-02-29 is taken into account. Real dates in
    /// January and February 1900 are one less than that count.
    static func excelSerial(iso: String) -> Int? {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1900...9999).contains(year),
              (1...12).contains(month)
        else { return nil }
        let leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
        let monthDays = [0, 31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...monthDays[month]).contains(day) else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
            - daysFromCivil(year: 1899, month: 12, day: 30)
        if year == 1900 && month < 3 {
            return days - 1
        }
        return days
    }

    /// Howard Hinnant's `days_from_civil`: days since 1970-01-01. Only differences are used.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var y = year
        let m = month
        if m <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let shiftedMonth = m + (m > 2 ? -3 : 9)
        let doy = (153 * shiftedMonth + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    private static func worksheetXML(_ sheet: XlsxSheet) -> String {
        var rows: [String] = []
        for (rowIndex, row) in sheet.rows.enumerated() {
            let rowNumber = rowIndex + 1
            let header = sheet.headerRow && rowIndex == 0
            let cells = row.enumerated().map { column, value in
                cell(column: column, row: rowNumber, cell: value, header: header)
            }.joined()
            rows.append("<row r=\"\(rowNumber)\">\(cells)</row>")
        }
        let views = sheet.headerRow
            ? "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/><selection pane=\"bottomLeft\" activeCell=\"A2\" sqref=\"A2\"/></sheetView></sheetViews>"
            : ""
        let cols = columnsXML(sheet.rows)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\(views)\(cols)<sheetData>\(rows.joined())</sheetData></worksheet>
        """
    }

    private static func columnsXML(_ rows: [[XlsxCell]]) -> String {
        let count = rows.map(\.count).max() ?? 0
        guard count > 0 else { return "" }
        var widths = Array(repeating: 10, count: count)
        for row in rows {
            for (index, cell) in row.enumerated() {
                let width = min(48, max(10, estimatedWidth(cell)))
                if width > widths[index] {
                    widths[index] = width
                }
            }
        }
        let cols = widths.enumerated().map { index, width in
            "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
        }.joined()
        return "<cols>\(cols)</cols>"
    }

    /// Character estimate plus a little extra so Cyrillic headers and `yyyy-mm-dd` do not clip.
    private static func estimatedWidth(_ cell: XlsxCell) -> Int {
        let characters: Int
        switch cell {
        case .blank:
            return 10
        case .text(let value):
            characters = value.count
        case .number(_, let format):
            switch format {
            case .date, .money: characters = 12
            case .decimal3, .decimal2, .integer: characters = 8
            }
        }
        return characters + characters / 5 + 2
    }

    private static func cell(column: Int, row: Int, cell: XlsxCell, header: Bool) -> String {
        let ref = "\(columnName(column))\(row)"
        if header {
            return inlineString(ref: ref, value: textContent(cell), style: " s=\"1\"")
        }
        switch cell {
        case .blank:
            return "<c r=\"\(ref)\"/>"
        case .text(let value):
            if value.isEmpty { return "<c r=\"\(ref)\"/>" }
            return inlineString(ref: ref, value: value, style: "")
        case .number(let raw, let format):
            guard isInvariantNumber(raw) else {
                return inlineString(ref: ref, value: raw, style: "")
            }
            return "<c r=\"\(ref)\" s=\"\(styleIndex(for: format))\"><v>\(raw)</v></c>"
        }
    }

    private static func inlineString(ref: String, value: String, style: String) -> String {
        let preserve = needsPreserve(value) ? " xml:space=\"preserve\"" : ""
        return "<c r=\"\(ref)\" t=\"inlineStr\"\(style)><is><t\(preserve)>\(xmlEscape(value))</t></is></c>"
    }

    private static func textContent(_ cell: XlsxCell) -> String {
        switch cell {
        case .text(let value): return value
        case .number(let raw, _): return raw
        case .blank: return ""
        }
    }

    /// Invariant numeric literal. Rejects localized decimals and leading zeros so `<v>` stays a real number.
    private static func isInvariantNumber(_ raw: String) -> Bool {
        raw.range(of: #"^-?(?:0|[1-9]\d*)(?:\.\d+)?$"#, options: .regularExpression) != nil
    }

    private static func needsPreserve(_ value: String) -> Bool {
        guard let first = value.first, let last = value.last else { return false }
        return first.isWhitespace || last.isWhitespace || value.contains("\n")
    }

    static func columnName(_ index: Int) -> String {
        var n = index
        var name = ""
        repeat {
            let remainder = n % 26
            name = String(UnicodeScalar(65 + remainder)!) + name
            n = n / 26 - 1
        } while n >= 0
        return name
    }
}

/// ZIP archive of stored entries (compression method 0) with UTF-8 names.
enum ZipStore {
    static func archive(_ files: [(String, Data)]) -> Data {
        var local = Data()
        var central = Data()
        for (name, payload) in files {
            let nameData = Data(name.utf8)
            let crc = CRC32.checksum(payload)
            let size = UInt32(payload.count)
            let offset = UInt32(local.count)
            local.append(localHeader(nameLength: nameData.count, crc: crc, size: size))
            local.append(nameData)
            local.append(payload)
            central.append(centralHeader(nameLength: nameData.count, crc: crc, size: size, offset: offset))
            central.append(nameData)
        }
        let centralOffset = UInt32(local.count)
        var end = Data()
        end.appendU32(0x06054b50)
        end.appendU16(0)
        end.appendU16(0)
        end.appendU16(UInt16(files.count))
        end.appendU16(UInt16(files.count))
        end.appendU32(UInt32(central.count))
        end.appendU32(centralOffset)
        end.appendU16(0)
        local.append(central)
        local.append(end)
        return local
    }

    /// 2026-01-01 00:00 in DOS date/time. A zero date is rejected by some unzip implementations.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = {
        let year = UInt16(2026 - 1980)
        return (year << 9) | (1 << 5) | 1
    }()

    private static func localHeader(nameLength: Int, crc: UInt32, size: UInt32) -> Data {
        var data = Data()
        data.appendU32(0x04034b50)
        data.appendU16(20)
        data.appendU16(1 << 11)
        data.appendU16(0)
        data.appendU16(dosTime)
        data.appendU16(dosDate)
        data.appendU32(crc)
        data.appendU32(size)
        data.appendU32(size)
        data.appendU16(UInt16(nameLength))
        data.appendU16(0)
        return data
    }

    private static func centralHeader(nameLength: Int, crc: UInt32, size: UInt32, offset: UInt32) -> Data {
        var data = Data()
        data.appendU32(0x02014b50)
        data.appendU16(20)
        data.appendU16(20)
        data.appendU16(1 << 11)
        data.appendU16(0)
        data.appendU16(dosTime)
        data.appendU16(dosDate)
        data.appendU32(crc)
        data.appendU32(size)
        data.appendU32(size)
        data.appendU16(UInt16(nameLength))
        data.appendU16(0)
        data.appendU16(0)
        data.appendU16(0)
        data.appendU16(0)
        data.appendU32(0)
        data.appendU32(offset)
        return data
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            if crc & 1 == 1 {
                crc = (crc >> 1) ^ 0xEDB88320
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendU16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendU32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
