import Foundation

/// Support email drafted on the device. The app never sends it; the system mail app does.
public enum ImprovementFeedbackMail {
    public static let supportEmail = "Truckorig@gmail.com"
    public static let displayName = "TruckoRig"

    public enum Topic: String, CaseIterable, Sendable {
        case add
        case improve
        case works
        case broken
    }

    public struct Draft: Equatable, Sendable {
        public var to: String
        public var subject: String
        public var body: String

        public init(to: String, subject: String, body: String) {
            self.to = to
            self.subject = subject
            self.body = body
        }
    }

    /// Empty text is rejected. The body keeps Android's `Тема:` label and names the OS on the last line.
    public static func compose(
        topic: Topic,
        message: String,
        topicLabel: String,
        appVersion: String,
        systemName: String,
        systemRelease: String
    ) -> Draft? {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let subject = "[\(displayName)] \(topicLabel)"
        let body = """
        Тема: \(topicLabel)

        \(text)

        —
        \(displayName) \(appVersion)
        \(systemName) \(systemRelease)
        """
        return Draft(to: supportEmail, subject: subject, body: body)
    }

    public static func mailtoURI(_ draft: Draft) -> String {
        "mailto:\(draft.to)?subject=\(formEncode(draft.subject))&body=\(formEncode(draft.body))"
    }

    /// `application/x-www-form-urlencoded`, with spaces as `%20` the way Android's mail link does it.
    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
