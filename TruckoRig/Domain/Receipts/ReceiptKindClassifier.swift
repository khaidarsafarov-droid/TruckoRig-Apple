import Foundation

/// What an OCR dump or file name most likely is.
public enum ReceiptKind: String, CaseIterable, Sendable {
    case load
    case paycheck
    case diesel
    case def
    case unknown
}

/// Scores OCR text against real journals: loads, paycheck, diesel, DEF.
///
/// Longer, more specific markers beat generic words like "total".
public enum ReceiptKindClassifier {

    private static let loadMarkers: [(Int, Rx)] = [
        (6, Rx(#"Trip[\s\-_]*ID|T-[A-Z0-9]{6,}"#)),
        (5, Rx(#"Total[\s\-_]*Rate|Line[\s\-_]*Haul|Pu[\s\-_]*address|Del[\s\-_]*address|Estimated[\s\-_]*Rate"#)),
        (4, Rx(#"Total[\s\-_]*Loaded[\s\-_]*Miles|Amazon[\s\-_]*Relay|rate[\s\-_]*confirmation|load[\s\-_]*confirmation|load[\s\-_]*information|IEL[\s\-_]*PO"#)),
        (3, Rx(#"\bPU#|\bP/U\s*#|\bDEL#|pickup|delivery|pick[\s\-_]*ups"#)),
    ]
    private static let paycheckMarkers: [(Int, Rx)] = [
        (7, Rx(#"Driver\s*Sett+e?ment|Settlement\s*Summary|Payee\s*ID|Driver\s*Statement|Weekly\s*Sett+e?ment|Owner\s*Operator\s*Sett+e?ment"#)),
        (6, Rx(#"Net\s*(?:Pay|Earnings|Settlement)|Gross\s*(?:Pay|Earnings)|Driver\s*Pay|зарплат"#)),
        (5, Rx(#"paycheck|pay\s*stub|settlement|оклад|pay\s*statement"#)),
        (4, Rx(#"Grand\s*Total|Settlement\s*Total|Take[\s-]*Home|Cutoff\s*Date|Week\s*Start|Pay\s*Period|Compensation\s*Summary"#)),
        (2, Rx(#"YTD|year[\s-]*to[\s-]*date"#)),
    ]
    private static let dieselMarkers: [(Int, Rx)] = [
        (6, Rx(#"\bdiesel\b|\bдизел|\bДТ\b|diesel\s*fuel|\bulsd\b|#2\s*diesel"#)),
        (5, Rx(#"fuel\s*receipt|fuel\s*sale|pump\s*total|reefer\s*fuel|топлив"#)),
        (4, Rx(#"gallons?|\bgal\b|price\s*per\s*gal|PPG|PPU|л\.?\s*ДТ"#)),
        (2, Rx(#"Pilot|Love'?s|Flying\s*J|TA\s*Petro|Fuel"#)),
    ]
    private static let defMarkers: [(Int, Rx)] = [
        (8, Rx(#"diesel\s*exhaust\s*fluid|мочевин"#)),
        (7, Rx(#"\bad[\s\-]?blue\b|\bbluedef\b"#)),
        (6, Rx(#"\bDEF\b|\bAdBlue\b"#)),
        (4, Rx(#"DEF\s*fill|DEF\s*gal"#)),
    ]

    public static func classify(_ text: String, fileName: String? = nil) -> ReceiptKind {
        let scores = scoreMap(text, fileName: fileName)
        let order: [ReceiptKind] = [.load, .paycheck, .diesel, .def]
        var best = ReceiptKind.unknown
        var bestScore = 0
        for kind in order {
            let value = scores[kind] ?? 0
            if value > bestScore {
                best = kind
                bestScore = value
            }
        }
        guard bestScore > 0 else { return .unknown }
        let load = scores[.load] ?? 0
        let def = scores[.def] ?? 0
        let diesel = scores[.diesel] ?? 0
        let pay = scores[.paycheck] ?? 0
        if load >= 6 && load >= pay && load >= diesel && load >= def { return .load }
        if def >= 6 && def >= diesel { return .def }
        if pay >= diesel && pay >= def && pay >= 4 { return .paycheck }
        if diesel >= 4 { return .diesel }
        return best
    }

    public static func scoreMap(_ text: String, fileName: String? = nil) -> [ReceiptKind: Int] {
        let source = combined(text, fileName: fileName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return Dictionary(uniqueKeysWithValues: ReceiptKind.allCases.map { ($0, 0) })
        }
        return [
            .load: score(source, loadMarkers),
            .paycheck: score(source, paycheckMarkers),
            .diesel: score(source, dieselMarkers),
            .def: score(source, defMarkers),
            .unknown: 0,
        ]
    }

    private static func score(_ text: String, _ markers: [(Int, Rx)]) -> Int {
        markers.reduce(0) { partial, marker in
            partial + (marker.1.containsMatch(in: text) ? marker.0 : 0)
        }
    }

    private static func combined(_ text: String, fileName: String?) -> String {
        [fileName?.replacingOccurrences(of: "-", with: " "), text]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}
