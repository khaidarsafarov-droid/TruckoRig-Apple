import Foundation

/// Validation and CSV helpers for parking, scales, wash and other expenses.
public enum MiscExpenseFields {
    public enum FormError: Equatable, Sendable {
        case amount
        case description
        case date
    }

    private static let dateISO = Rx(#"^\d{4}-\d{2}-\d{2}$"#, options: [])

    public static func parseAmount(_ raw: String) -> Double? {
        DecimalInput.parse(raw).flatMap { $0 > 0 ? $0 : nil }
    }

    public static func validate(amountText: String, description: String, dateISO rawDate: String) -> FormError? {
        if parseAmount(amountText) == nil { return .amount }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .description }
        let trimmed = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = dateISO.firstMatch(in: trimmed), match.range == trimmed.startIndex..<trimmed.endIndex else {
            return .date
        }
        return nil
    }

    public static func csvQuote(_ value: String) -> String {
        let needsQuote = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuote else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    public static func csv(rows: [(date: String, description: String, amount: Double, receipt: String)]) -> String {
        var lines = ["date,description,amount,receipt"]
        for row in rows {
            lines.append(
                [
                    csvQuote(row.date),
                    csvQuote(row.description),
                    csvQuote(String(format: "%.2f", row.amount)),
                    csvQuote(row.receipt),
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
