import Foundation

/// Pulls visible text out of a Word `document.xml` or an Excel `sharedStrings.xml`.
///
/// The zip container is opened by the app. This step only reads the XML so the extraction can be
/// tested without UIKit.
public enum OfficeXMLText {
    public static func plainText(xml: String) -> String {
        let pattern = #"<(?:w:t|t)(?:\s[^>]*)?>(.*?)</(?:w:t|t)>"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return ""
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = expression.matches(in: xml, range: range)
        let pieces = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1, let span = Range(match.range(at: 1), in: xml) else { return nil }
            let text = decode(String(xml[span])).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        return pieces.joined(separator: "\n")
    }

    private static func decode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
