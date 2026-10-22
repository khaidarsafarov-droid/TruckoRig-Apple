import Foundation

struct TelegramReceiptDraft: Codable, Equatable {
    var kind: String
    var amount: Double?
    var text: String
    var awaitingTyped: Bool
    var date: Int64?
    var gallons: Double?
    var pricePerGallon: Double?
    var location: String?
    var driverName: String?
    var weekHint: String?
    var fileName: String?
}

struct TelegramTeachDraft: Codable, Equatable {
    var phase: String
    var body: String
    var tripLabel: String
}

struct TelegramStash: Codable, Equatable {
    var updateId: Int64
    var chatId: String
    var text: String
    var date: Int64?
}

/// Everything except the bot token. The token stays in the Keychain.
final class TelegramPrefs {
    private let defaults: UserDefaults
    private let prefix: String

    init(scope: AccountScope = .local, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.prefix = "truckorig.\(scope.storeKey).telegram."
    }

    var chatId: Int64? {
        get {
            let value = defaults.object(forKey: key("chat")) as? NSNumber
            return value?.int64Value
        }
        set {
            if let newValue { defaults.set(NSNumber(value: newValue), forKey: key("chat")) }
            else { defaults.removeObject(forKey: key("chat")) }
        }
    }

    var pairingCode: String {
        get { defaults.string(forKey: key("pair")) ?? "" }
        set { defaults.set(newValue, forKey: key("pair")) }
    }

    var offset: Int64 {
        get { (defaults.object(forKey: key("offset")) as? NSNumber)?.int64Value ?? 0 }
        set { defaults.set(NSNumber(value: newValue), forKey: key("offset")) }
    }

    var hinted: Set<String> {
        get { Set(defaults.stringArray(forKey: key("hinted")) ?? []) }
        set { defaults.set(Array(newValue), forKey: key("hinted")) }
    }

    var importing: Set<String> {
        get { Set(defaults.stringArray(forKey: key("importing")) ?? []) }
        set { defaults.set(Array(newValue), forKey: key("importing")) }
    }

    var nameStamp: String {
        get { defaults.string(forKey: key("nameStamp")) ?? "" }
        set { defaults.set(newValue, forKey: key("nameStamp")) }
    }

    var photoStamp: String {
        get { defaults.string(forKey: key("photoStamp")) ?? "" }
        set { defaults.set(newValue, forKey: key("photoStamp")) }
    }

    var lastLoadId: String? {
        get { defaults.string(forKey: key("lastLoad")) }
        set {
            if let newValue { defaults.set(newValue, forKey: key("lastLoad")) }
            else { defaults.removeObject(forKey: key("lastLoad")) }
        }
    }

    var lastLoadTrip: String? {
        get { defaults.string(forKey: key("lastTrip")) }
        set {
            if let newValue { defaults.set(newValue, forKey: key("lastTrip")) }
            else { defaults.removeObject(forKey: key("lastTrip")) }
        }
    }

    func restoreFlag(_ chatId: String) -> Bool { defaults.bool(forKey: key("restore.\(chatId)")) }

    func setRestore(_ chatId: String, active: Bool, now: Date = Date()) {
        if active {
            defaults.set(true, forKey: key("restore.\(chatId)"))
            defaults.set(now.timeIntervalSince1970, forKey: key("restoreAt.\(chatId)"))
        } else {
            defaults.removeObject(forKey: key("restore.\(chatId)"))
            defaults.removeObject(forKey: key("restoreAt.\(chatId)"))
        }
    }

    func touchRestore(_ chatId: String, now: Date = Date()) {
        defaults.set(now.timeIntervalSince1970, forKey: key("restoreAt.\(chatId)"))
    }

    func restoreIsActive(_ chatId: String, now: Date = Date()) -> Bool {
        let flagged = restoreFlag(chatId)
        let last = defaults.double(forKey: key("restoreAt.\(chatId)"))
        let lastMs = Int64(last * 1000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let active = TelegramSyncRules.restoreIsActive(lastActivityMs: lastMs, nowMs: nowMs, flagged: flagged)
        if flagged && !active { setRestore(chatId, active: false, now: now) }
        return active
    }

    func receipt(_ chatId: String) -> TelegramReceiptDraft? { decode(key("pending-receipt.\(chatId)")) }
    func setReceipt(_ chatId: String, _ draft: TelegramReceiptDraft?) { encode(key("pending-receipt.\(chatId)"), draft) }

    func teach(_ chatId: String) -> TelegramTeachDraft? { decode(key("teach.\(chatId)")) }
    func setTeach(_ chatId: String, _ draft: TelegramTeachDraft?) { encode(key("teach.\(chatId)"), draft) }

    func stash() -> [TelegramStash] { decode(key("stash")) ?? [] }
    func setStash(_ rows: [TelegramStash]) { encode(key("stash"), rows) }

    func poison(_ updateId: Int64) -> Int { defaults.integer(forKey: key("poison.\(updateId)")) }
    func setPoison(_ updateId: Int64, _ count: Int) {
        if count <= 0 { defaults.removeObject(forKey: key("poison.\(updateId)")) }
        else { defaults.set(count, forKey: key("poison.\(updateId)")) }
    }

    func ensurePairingCode() -> String {
        if !pairingCode.isEmpty { return pairingCode }
        var bytes = [UInt8](repeating: 0, count: TelegramPairingCode.length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess { bytes = (0..<TelegramPairingCode.length).map { _ in UInt8.random(in: 0...255) } }
        let code = TelegramPairingCode.make(bytes: bytes)
        pairingCode = code
        return code
    }

    func clearPairing() {
        chatId = nil
        pairingCode = ""
        hinted = []
    }

    private func key(_ name: String) -> String { prefix + name }

    private func decode<T: Decodable>(_ name: String) -> T? {
        guard let data = defaults.data(forKey: name) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ name: String, _ value: T?) {
        guard let value else {
            defaults.removeObject(forKey: name)
            return
        }
        defaults.set(try? JSONEncoder().encode(value), forKey: name)
    }
}
