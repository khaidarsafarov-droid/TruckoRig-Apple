import Foundation

/// One journal row in a spreadsheet export.
public struct LoadCSVRecord: Equatable, Sendable {
    public var tripId: String
    /// `YYYY-MM-DD`.
    public var date: String
    public var pointA: String
    public var pointB: String
    public var totalRate: Double
    public var totalMiles: Double
    public var stopCount: Int
    public var weekNumber: Int
    public var year: Int

    public init(
        tripId: String,
        date: String,
        pointA: String,
        pointB: String,
        totalRate: Double,
        totalMiles: Double,
        stopCount: Int = 0,
        weekNumber: Int = 0,
        year: Int = 0
    ) {
        self.tripId = tripId
        self.date = date
        self.pointA = pointA
        self.pointB = pointB
        self.totalRate = totalRate
        self.totalMiles = totalMiles
        self.stopCount = stopCount
        self.weekNumber = weekNumber
        self.year = year
    }

    public var ratePerMile: Double {
        RPMCalculator.ratePerMile(rate: totalRate, miles: totalMiles)
    }
}

/// RFC 4180 CSV round-trip for the journal.
///
/// Accountants open these in Excel and send them back edited, so parsing has to tolerate quoted
/// commas, embedded newlines and a reordered header row.
public enum CSVExportParser {

    public static let header = [
        "trip_id", "date", "point_a", "point_b", "total_rate", "total_miles", "rpm",
        "stops", "week", "year",
    ]

    // MARK: - Export

    public static func csv(from records: [LoadCSVRecord]) -> String {
        var lines = [header.joined(separator: ",")]
        for record in records {
            lines.append([
                escape(record.tripId),
                escape(record.date),
                escape(record.pointA),
                escape(record.pointB),
                format(record.totalRate),
                format(record.totalMiles),
                format(record.ratePerMile),
                String(record.stopCount),
                String(record.weekNumber),
                String(record.year),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Import

    public static func parse(_ csv: String) -> [LoadCSVRecord] {
        let rows = tokenize(csv)
        guard let headerRow = rows.first else { return [] }
        let columns = headerRow.map { normalizeHeader($0) }

        func value(_ row: [String], _ names: [String]) -> String {
            for name in names {
                if let index = columns.firstIndex(of: name), index < row.count {
                    return row[index].trimmingCharacters(in: .whitespaces)
                }
            }
            return ""
        }

        return rows.dropFirst().compactMap { row in
            guard row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
            let tripId = TripID.normalize(value(row, ["trip_id", "tripid", "trip"]))
            guard !tripId.isEmpty else { return nil }
            return LoadCSVRecord(
                tripId: tripId,
                date: value(row, ["date"]),
                pointA: value(row, ["point_a", "pointa", "origin", "from"]),
                pointB: value(row, ["point_b", "pointb", "destination", "to"]),
                totalRate: NumberParsing.parseMoney(value(row, ["total_rate", "rate", "gross"])),
                totalMiles: NumberParsing.parseMiles(value(row, ["total_miles", "miles"])),
                stopCount: Int(value(row, ["stops", "stop_count"])) ?? 0,
                weekNumber: Int(value(row, ["week", "week_number"])) ?? 0,
                year: Int(value(row, ["year"])) ?? 0
            )
        }
    }

    private static func normalizeHeader(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    /// Splits CSV text into rows of fields, honouring quotes and doubled escapes.
    static func tokenize(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = csv.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }

            switch character {
            case "\"": inQuotes = true
            case ",": endField()
            case "\n": endRow()
            case "\r": break
            default: field.append(character)
            }
        }

        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
