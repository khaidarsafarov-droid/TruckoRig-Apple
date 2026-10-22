import Foundation

/// Decides whether a build setting is a Maps SDK key the app may hand to Google.
///
/// An empty value, an unsubstituted `$(GOOGLE_MAPS_API_KEY)`, and the example placeholders
/// all mean "not configured". The map then shows a message instead of constructing a map view.
public enum MapsAPIKey {
    public static let placeholders: Set<String> = [
        "YOUR_API_KEY",
        "REPLACE_WITH_GOOGLE_MAPS_API_KEY",
    ]

    public static func sanitized(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        if trimmed.contains("$(") { return "" }
        if placeholders.contains(trimmed) { return "" }
        return trimmed
    }

    public static func isConfigured(_ raw: String?) -> Bool {
        !sanitized(raw).isEmpty
    }
}
