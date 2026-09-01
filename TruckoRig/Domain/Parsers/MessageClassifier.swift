import Foundation

/// What a pasted or forwarded message looks like.
public enum MessageKind: String, Sendable {
    case load
    case paycheck
    case diesel
    case unknown
}

/// Keyword classification of inbound text. No network, no model — just markers.
public enum MessageClassifier {

    private static let loadMarkers = Rx(
        #"Trip\s*ID|Trip\nID|PU#|P/U\s*#|Total\s*Rate|rate[\s\-]*confirmation|"#
            + #"load[\s\-]*confirmation|estimated\s*rate|load\s*information"#
    )
    private static let paycheckMarkers = Rx(
        #"Grand\s*Total|Settlement\s*Date|Cutoff\s*Date|Driver\s*Settlement|Зарплата|Net\s*Pay|Gross\s*Pay"#
    )
    private static let dieselMarkers = Rx(
        #"diesel|fuel\s*receipt|gallons?|price\s*per\s*gallon|gal\s*@|топлив|дизел"#
    )

    public static func classify(_ text: String) -> MessageKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }
        if loadMarkers.containsMatch(in: trimmed) { return .load }
        if paycheckMarkers.containsMatch(in: trimmed) { return .paycheck }
        if dieselMarkers.containsMatch(in: trimmed) { return .diesel }
        return .unknown
    }

    public static func isLoadLike(_ text: String) -> Bool {
        loadMarkers.containsMatch(in: text)
    }
}
