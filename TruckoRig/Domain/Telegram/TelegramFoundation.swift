import Foundation

/// App language the bot replies in. `.system` follows the device identifier (`ru` → Russian).
public enum TelegramLanguage: String, Equatable, Sendable {
    case en
    case ru
    case fr

    public static func resolve(appLanguage: String, deviceIdentifier: String) -> TelegramLanguage {
        switch appLanguage {
        case "russian": return .ru
        case "english": return .en
        case "french": return .fr
        default:
            let identifier = deviceIdentifier.lowercased()
            if identifier.hasPrefix("ru") { return .ru }
            if identifier.hasPrefix("fr") { return .fr }
            return .en
        }
    }
}

/// Substitutes Android `%1$s` / `%1$d` / `%1$.2f` with already-rendered arguments.
public enum TelegramFormat {
    public static func apply(_ template: String, _ args: [String]) -> String {
        var result = template.replacingOccurrences(of: "%%", with: "\u{0000}")
        for index in stride(from: args.count, through: 1, by: -1) {
            let value = args[index - 1]
            result = result
                .replacingOccurrences(of: "%\(index)$.2f", with: value)
                .replacingOccurrences(of: "%\(index)$s", with: value)
                .replacingOccurrences(of: "%\(index)$d", with: value)
        }
        return result.replacingOccurrences(of: "\u{0000}", with: "%")
    }
}

/// SHA-256. The bot fingerprint and diesel dedupe hash must match Android's `MessageDigest`.
public enum TelegramSHA256 {
    public static func digest(_ message: [UInt8]) -> [UInt8] {
        var hash: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        ]
        var bytes = message
        let bitLength = UInt64(message.count) * 8
        bytes.append(0x80)
        while (bytes.count % 64) != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        func rotr(_ value: UInt32, _ count: UInt32) -> UInt32 {
            (value >> count) | (value << (32 - count))
        }
        var index = 0
        while index < bytes.count {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j = index + i * 4
                w[i] = (UInt32(bytes[j]) << 24) | (UInt32(bytes[j + 1]) << 16) | (UInt32(bytes[j + 2]) << 8) | UInt32(bytes[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
            var e = hash[4], f = hash[5], g = hash[6], h = hash[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            hash[0] = hash[0] &+ a; hash[1] = hash[1] &+ b; hash[2] = hash[2] &+ c; hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e; hash[5] = hash[5] &+ f; hash[6] = hash[6] &+ g; hash[7] = hash[7] &+ h
            index += 64
        }
        var out: [UInt8] = []
        out.reserveCapacity(32)
        for word in hash {
            out.append(UInt8((word >> 24) & 0xff))
            out.append(UInt8((word >> 16) & 0xff))
            out.append(UInt8((word >> 8) & 0xff))
            out.append(UInt8(word & 0xff))
        }
        return out
    }

    public static func hex(_ text: String) -> String {
        digest(Array(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// First 8 bytes, the stamp Android stores so branding runs once per bot.
    public static func fingerprint(_ token: String) -> String {
        String(hex(token).prefix(16))
    }
}

/// Strips bot tokens, JWTs, and bearer secrets out of Telegram error text before it is shown or logged.
public enum TelegramRedactor {
    public static func redact(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return raw ?? "" }
        var text = raw
        text = replace(text, #"/bot[0-9]+:[A-Za-z0-9_-]+"#, "/bot***")
        text = replace(text, #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, "***jwt***")
        text = replace(text, #"(?i)(Bearer\s+)([A-Za-z0-9._\-+=/]+)"#, "$1***")
        text = replace(text, #"AIza[0-9A-Za-z_\-]{10,}"#, "***gkey***")
        return text
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

/// BotFather tokens look like `123456789:AAH…`. Junk is rejected before any request.
public enum TelegramTokenRules {
    public static func isPlausible(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^\d{5,16}:[A-Za-z0-9_-]{20,}$"#) else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }

    public static func normalized(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Display name and the photo stamp Android writes after `setMyName` / `setMyProfilePhoto`.
public enum TelegramBranding {
    public static let displayName = "TruckoRig"
    public static let photoRevision = "midnight-gold"
    public static let nameKey = "bot_display_name_fp"
    public static let photoKey = "bot_profile_photo_fp"

    public static func nameStamp(_ token: String) -> String {
        TelegramSHA256.fingerprint(token) + ":" + displayName
    }

    public static func photoStamp(_ token: String) -> String {
        TelegramSHA256.fingerprint(token) + ":" + photoRevision
    }

    public static func setMyNameBody() -> String {
        #"{"name":"\#(displayName)"}"#
    }

    /// Multipart field Telegram requires: a static attach named `logo`.
    public static let profilePhotoAttachJSON = #"{"type":"static","photo":"attach://logo"}"#

    public static func isJPEG(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF
    }
}

/// US-grouped money and miles for bot replies. The device locale must not change the digits.
public enum TelegramFigures {
    public static func money(_ amount: Double) -> String {
        let cents = Int64((amount * 100).rounded())
        let sign = cents < 0 ? "-" : ""
        let absolute = abs(cents)
        let dollars = absolute / 100
        let fraction = absolute % 100
        return sign + grouped(dollars) + String(format: ".%02d", fraction)
    }

    public static func dollars(_ cents: Int64) -> String {
        let sign = cents < 0 ? "-" : ""
        let absolute = abs(cents)
        let dollars = absolute / 100
        let fraction = absolute % 100
        return "$" + sign + grouped(dollars) + "." + String(format: "%02d", fraction)
    }

    public static func miles(_ miles: Double) -> String {
        let tenths = (miles * 10).rounded() / 10
        if abs(tenths - tenths.rounded()) < 0.05 {
            return String(Int64(tenths.rounded()))
        }
        return String(format: "%.1f", tenths)
    }

    public static func grouped(_ value: Int64) -> String {
        let digits = String(value)
        var out = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(character)
        }
        return out
    }

    public static func plainGrouped(_ amount: Double) -> String {
        money(amount)
    }
}

public struct TelegramLoadReply: Equatable, Sendable {
    public static func route(origin: String, destination: String) -> String {
        let from = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if !from.isEmpty && !to.isEmpty { return "\(from) → \(to)" }
        if !from.isEmpty { return from }
        return to
    }

    public static func detail(
        rate: Double,
        miles: Double,
        origin: String,
        destination: String,
        system: MeasurementSystem = .miles
    ) -> String {
        let money = rate > 0 ? TelegramFigures.dollars(Int64((rate * 100).rounded())) : ""
        let shown = MeasurementUnits.displayDistance(miles, system: system)
        let suffix = system == .kilometers ? "km" : "mi"
        let milesText = miles > 0 ? "\(TelegramFigures.miles(shown)) \(suffix)" : ""
        let figures = [money, milesText].filter { !$0.isEmpty }.joined(separator: " · ")
        let route = route(origin: origin, destination: destination)
        return [figures, route].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
