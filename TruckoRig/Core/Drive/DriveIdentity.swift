import Foundation

/// Stable ids and Android-only fields that the iOS tables do not have a column for.
///
/// The `.tlb` file keeps Android's id types (load `String`, stop/paycheck/diesel `Int`,
/// maintenance `Long`). Re-exporting the same phone has to write those ids again, so the map
/// is persisted. It is not part of the backup and is not cleared on Drive disconnect.
struct DriveIdentityBook: Codable, Equatable {
    var loadAndroidByUUID: [String: String] = [:]
    var loadUUIDByAndroid: [String: String] = [:]
    var stopUUIDByKey: [String: String] = [:]
    var stopIntByUUID: [String: Int] = [:]
    var penaltyUUIDByKey: [String: String] = [:]
    var penaltyIntByUUID: [String: Int] = [:]
    var paycheckUUIDByAndroid: [String: String] = [:]
    var paycheckIntByUUID: [String: Int] = [:]
    var dieselUUIDByAndroid: [String: String] = [:]
    var dieselIntByUUID: [String: Int] = [:]
    var maintenanceIDByLong: [String: String] = [:]
    var maintenanceLongByID: [String: Int64] = [:]

    var loadExtras: [String: DriveLoadExtra] = [:]
    var paycheckExtras: [String: DrivePaycheckExtra] = [:]
    var dieselExtras: [String: DriveDieselExtra] = [:]
    var penaltyDates: [String: Double] = [:]
    var settingsExtra: DriveSettingsExtra = DriveSettingsExtra()
}

struct DriveLoadExtra: Codable, Equatable {
    var equipmentType: String?
    var deadheadMiles: Double = 0
    var disputeApplyToLoad: Bool = false
    var disputeAmountApplied: Bool = false
}

struct DrivePaycheckExtra: Codable, Equatable {
    var company: String?
    var notes: String?
    var weekLabel: String?
    var weekStartDate: String?
    var weekEndDate: String?
    var sourceFilePath: String?
    var addedAt: Int64?
}

struct DriveDieselExtra: Codable, Equatable {
    var state: String?
    var odometer: Int?
    var receiptFileName: String?
    var weekLabel: String?
    var weekStartDate: String?
    var weekEndDate: String?
    var addedAt: Int64?
}

/// Android settings this phone does not edit. Written back so a round trip does not drop them.
struct DriveSettingsExtra: Codable, Equatable {
    var themeModeOrdinal: Int?
    var reduceMotion: Bool?
    var oledDark: Bool?
    var dynamicColor: Bool?
    var parserAutoUpdate: Bool?
    var parserPriceThresholdPercent: Double?
    var lastEquipmentType: String?
    /// Android Spanish. iOS has no Spanish UI, so the ordinal is kept and the UI shows English.
    var preservedLanguageOrdinal: Int?
}

final class DriveIdentityStore {
    private let defaults: UserDefaults
    private let key = "book"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func standard(accountId: String = DriveAccount.localDev) -> DriveIdentityStore {
        let name = DriveAccount.prefsName(accountId: accountId) + "_identity"
        return DriveIdentityStore(defaults: UserDefaults(suiteName: name) ?? .standard)
    }

    func load() -> DriveIdentityBook {
        guard let data = defaults.data(forKey: key) else { return DriveIdentityBook() }
        return (try? JSONDecoder().decode(DriveIdentityBook.self, from: data)) ?? DriveIdentityBook()
    }

    func save(_ book: DriveIdentityBook) {
        guard let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: key)
    }
}

enum DriveIdentity {
    /// Same text always maps to the same UUID. The version nibble marks it as an app-assigned id.
    static func deterministicUUID(_ text: String) -> UUID {
        var high = UInt64(14_695_981_039_346_656_037)
        var low = UInt64(10_995_116_282_211)
        for byte in text.utf8 {
            high ^= UInt64(byte)
            high &*= 10_995_116_282_211
            low ^= UInt64(byte)
            low &*= 14_695_981_039_346_656_037
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((high >> (8 * index)) & 0xff)
            bytes[8 + index] = UInt8((low >> (8 * index)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func positiveInt(for key: String, saved: inout [String: Int], used: inout Set<Int>) -> Int {
        if let existing = saved[key], existing > 0, !used.contains(existing) {
            used.insert(existing)
            return existing
        }
        var hash = UInt64(14_695_981_039_346_656_037)
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 10_995_116_282_211
        }
        var candidate = Int(hash % 1_900_000_000) + 1
        while used.contains(candidate) {
            candidate = candidate >= 1_900_000_000 ? 1 : candidate + 1
        }
        used.insert(candidate)
        saved[key] = candidate
        return candidate
    }

    static func positiveLong(for key: String, saved: inout [String: Int64], used: inout Set<Int64>) -> Int64 {
        if let existing = saved[key], existing > 0, !used.contains(existing) {
            used.insert(existing)
            return existing
        }
        if let digits = Int64(key), key.allSatisfy({ $0.isNumber }), digits > 0, !used.contains(digits) {
            used.insert(digits)
            saved[key] = digits
            return digits
        }
        var hash = UInt64(14_695_981_039_346_656_037)
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 10_995_116_282_211
        }
        var candidate = Int64(hash % 9_000_000_000_000_000) + 1
        while used.contains(candidate) {
            candidate = candidate >= 9_000_000_000_000_000 ? 1 : candidate + 1
        }
        used.insert(candidate)
        saved[key] = candidate
        return candidate
    }
}
