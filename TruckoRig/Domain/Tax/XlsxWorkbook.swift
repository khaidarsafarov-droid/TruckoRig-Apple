import Foundation

/// One worksheet in an OOXML workbook. Cell values are text, matching the Android
/// accountant export, which writes every SpreadsheetML cell as `ss:Type="String"`.
public struct XlsxSheet: Equatable, Sendable {
    public var name: String
    public var rows: [[String]]
    /// When true, the first row uses the header style (bold, fill `#E6EDE9`).
    public var headerRow: Bool

    public init(name: String, rows: [[String]], headerRow: Bool) {
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

    /// Header fill `#E6EDE9` and the unused money format `#,##0.00`, same as Android's Styles block.
    /// Android defines the money format and then writes every value as text, so no cell uses it.
    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00"/></numFmts>
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
      <cellXfs count="2">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
      </cellXfs>
    </styleSheet>
    """

    private static func worksheetXML(_ sheet: XlsxSheet) -> String {
        var rows: [String] = []
        for (rowIndex, row) in sheet.rows.enumerated() {
            let rowNumber = rowIndex + 1
            let header = sheet.headerRow && rowIndex == 0
            let cells = row.enumerated().map { column, value in
                cell(column: column, row: rowNumber, value: value, header: header)
            }.joined()
            rows.append("<row r=\"\(rowNumber)\">\(cells)</row>")
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows.joined())</sheetData></worksheet>
        """
    }

    private static func cell(column: Int, row: Int, value: String, header: Bool) -> String {
        let ref = "\(columnName(column))\(row)"
        let style = header ? " s=\"1\"" : ""
        let preserve = needsPreserve(value) ? " xml:space=\"preserve\"" : ""
        return "<c r=\"\(ref)\" t=\"inlineStr\"\(style)><is><t\(preserve)>\(xmlEscape(value))</t></is></c>"
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
