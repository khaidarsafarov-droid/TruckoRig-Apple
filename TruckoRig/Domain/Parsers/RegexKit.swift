import Foundation

/// One regex hit with its capture groups already converted back to `String`.
struct RxMatch {
    let groups: [String?]
    let range: Range<String.Index>

    /// Trimmed capture group, or `nil` when the group did not participate or is blank.
    func group(_ index: Int) -> String? {
        guard index < groups.count, let value = groups[index] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func groupOrEmpty(_ index: Int) -> String { group(index) ?? "" }
}

/// Thin ergonomic wrapper over `NSRegularExpression`.
///
/// The parsers are ports of Kotlin `Regex` code, so keeping ICU semantics (rather than switching to
/// Swift `Regex` literals) keeps their behaviour identical on both clients.
struct Rx {
    /// `nil` when the pattern literal is malformed. A bad literal is a programming error, and
    /// degrading to "never matches" keeps a driver's paste from crashing the app.
    private let regex: NSRegularExpression?

    init(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
        regex = try? NSRegularExpression(pattern: pattern, options: options)
    }

    func firstMatch(in string: String) -> RxMatch? {
        matches(in: string).first
    }

    func matches(in string: String) -> [RxMatch] {
        guard let regex else { return [] }
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, options: [], range: nsRange).compactMap { result in
            guard let range = Range(result.range, in: string) else { return nil }
            let groups = (0..<result.numberOfRanges).map { index -> String? in
                guard let groupRange = Range(result.range(at: index), in: string) else { return nil }
                return String(string[groupRange])
            }
            return RxMatch(groups: groups, range: range)
        }
    }

    func containsMatch(in string: String) -> Bool {
        guard let regex else { return false }
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, options: [], range: nsRange) != nil
    }

    /// First non-blank capture group 1 across `patterns`, in order.
    static func firstCapture(in string: String, patterns: [Rx]) -> String? {
        for pattern in patterns {
            if let value = pattern.firstMatch(in: string)?.group(1) { return value }
        }
        return nil
    }
}
