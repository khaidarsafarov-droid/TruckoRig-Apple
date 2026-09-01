import Foundation

/// Recognises text that looks like a load message.
///
/// The Android client also classifies paychecks and fuel receipts because a Telegram bot feeds it
/// arbitrary messages. On iOS the only entry point is the driver pasting a trip, so this stays a
/// single question: is this a load?
public enum MessageClassifier {

    private static let loadMarkers = Rx(
        #"Trip\s*ID|Trip\nID|PU#|P/U\s*#|Total\s*Rate|rate[\s\-]*confirmation|"#
            + #"load[\s\-]*confirmation|estimated\s*rate|load\s*information"#
    )

    public static func isLoadLike(_ text: String) -> Bool {
        loadMarkers.containsMatch(in: text)
    }
}
