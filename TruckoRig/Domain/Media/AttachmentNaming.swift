import Foundation

/// Builds attachment file names from a load's Trip ID and date,
/// e.g. `114RS221Y_2026-07-21_143052.jpg`.
///
/// Port of Android `AttachmentNaming`.
public enum AttachmentNaming {

    public static func sanitize(_ part: String) -> String {
        let replaced = part.trimmingCharacters(in: .whitespacesAndNewlines).map { character -> Character in
            if character.isASCII && (character.isLetter || character.isNumber || "._-".contains(character)) {
                return character
            }
            return "_"
        }
        var collapsed = ""
        var previousWasUnderscore = false
        for character in replaced {
            if character == "_" {
                if previousWasUnderscore { continue }
                previousWasUnderscore = true
            } else {
                previousWasUnderscore = false
            }
            collapsed.append(character)
        }
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "file" : trimmed
    }

    public static func buildFileName(
        tripId: String,
        loadDate: String,
        timestamp: Date = Date(),
        extension ext: String,
        timeZone: TimeZone = .current
    ) -> String {
        let trimmedDate = loadDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let datePart = trimmedDate.isEmpty
            ? MediaClock.format(timestamp, pattern: "yyyy-MM-dd", timeZone: timeZone)
            : trimmedDate
        let cleanedExtension = ext.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedExtension = cleanedExtension.isEmpty ? "bin" : cleanedExtension
        let base = "\(sanitize(tripId))_\(sanitize(datePart))"
        let time = MediaClock.format(timestamp, pattern: "HHmmss", timeZone: timeZone)
        return "\(base)_\(time).\(resolvedExtension)"
    }
}
