import Foundation

/// App Group id shared by the app, the widget, and the share extension.
public enum ShareImportLocation {
    public static let appGroupIdentifier = "group.com.truckorig"
    /// Darwin notification the extension posts after it writes the inbox.
    /// A suspended app does not wake for it; the next foreground pass reads the inbox.
    public static let darwinNotification = "com.truckorig.share-import"
    /// Custom URL the extension asks the system to open. Unknown paths already land on the journal.
    public static let openURLString = "truckorig://share"
}

/// A field the share import did not find. The load is still saved when the score is high enough.
public enum ShareLoadMissing: String, Codable, CaseIterable, Equatable, Sendable {
    case tripId
    case broker
    case origin
    case destination
    case pickupDate
    case deliveryDate
    case miles
}

/// Fields pulled out of one shared load. `tripId` is the printed load number, not the storage key
/// the journal uses when two brokers reuse a number.
public struct ShareLoadFields: Codable, Equatable, Sendable {
    public var tripId: String
    public var broker: String
    public var origin: String
    public var destination: String
    public var pickupDate: Date?
    public var deliveryDate: Date?
    public var rate: Double
    public var miles: Double
    public var missing: [ShareLoadMissing]
    public var score: Int

    public init(
        tripId: String,
        broker: String,
        origin: String,
        destination: String,
        pickupDate: Date?,
        deliveryDate: Date?,
        rate: Double,
        miles: Double,
        missing: [ShareLoadMissing],
        score: Int
    ) {
        self.tripId = tripId
        self.broker = broker
        self.origin = origin
        self.destination = destination
        self.pickupDate = pickupDate
        self.deliveryDate = deliveryDate
        self.rate = rate
        self.miles = miles
        self.missing = missing
        self.score = score
    }
}

public enum ShareRejectReason: Equatable, Sendable {
    case empty
    case notALoad
    case otherDocument
}

public enum ShareLoadVerdict: Equatable, Sendable {
    case accepted([ShareLoadFields])
    case rejected(ShareRejectReason)
}

/// Identity used to skip a second copy of the same load.
public struct ShareImportFingerprint: Codable, Equatable, Sendable {
    public var tripId: String
    public var broker: String
    public var fileSHA256: String?

    public init(tripId: String, broker: String, fileSHA256: String?) {
        self.tripId = tripId
        self.broker = broker
        self.fileSHA256 = fileSHA256
    }
}

public enum ShareImportDeduper {
    /// Same file hash, or the same load number when the brokers are not both present and different.
    ///
    /// A blank broker matches any broker on that load number. Two different printed broker names
    /// with the same load number are kept as two loads.
    public static func isDuplicate(_ candidate: ShareImportFingerprint, among existing: [ShareImportFingerprint]) -> Bool {
        let trip = TripID.normalize(candidate.tripId)
        let broker = normalizeBroker(candidate.broker)
        let file = normalizedHash(candidate.fileSHA256)
        for item in existing {
            if let file, let other = normalizedHash(item.fileSHA256), file == other {
                return true
            }
            if sameLoad(trip: trip, broker: broker, as: item) { return true }
        }
        return false
    }

    /// `saved` is the journal and older inbox rows, so a repeated file is a duplicate.
    /// `batch` is what this share already accepted: a second load in that same file is kept
    /// when its load number and broker differ.
    public static func isDuplicate(
        _ candidate: ShareImportFingerprint,
        saved: [ShareImportFingerprint],
        batch: [ShareImportFingerprint]
    ) -> Bool {
        if isDuplicate(candidate, among: saved) { return true }
        let withoutFile = ShareImportFingerprint(tripId: candidate.tripId, broker: candidate.broker, fileSHA256: nil)
        let batchLoads = batch.map { ShareImportFingerprint(tripId: $0.tripId, broker: $0.broker, fileSHA256: nil) }
        return isDuplicate(withoutFile, among: batchLoads)
    }

    private static func sameLoad(trip: String, broker: String, as item: ShareImportFingerprint) -> Bool {
        let otherTrip = TripID.normalize(item.tripId)
        guard !trip.isEmpty, trip == otherTrip else { return false }
        let otherBroker = normalizeBroker(item.broker)
        return broker.isEmpty || otherBroker.isEmpty || broker == otherBroker
    }

    public static func normalizeBroker(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func normalizedHash(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty || trimmed == "-" ? nil : trimmed
    }
}

/// One accepted share, waiting in the App Group until the app is in the foreground.
public struct ShareImportRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var sourceText: String
    public var fileSHA256: String?
    public var originalFileName: String?
    public var storedFileName: String?
    public var pageCount: Int
    public var load: ShareLoadFields

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        sourceText: String,
        fileSHA256: String? = nil,
        originalFileName: String? = nil,
        storedFileName: String? = nil,
        pageCount: Int = 0,
        load: ShareLoadFields
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceText = sourceText
        self.fileSHA256 = fileSHA256
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.pageCount = pageCount
        self.load = load
    }

    public var fingerprint: ShareImportFingerprint {
        ShareImportFingerprint(tripId: load.tripId, broker: load.broker, fileSHA256: fileSHA256)
    }
}

public struct ShareImportIndex: Codable, Equatable, Sendable {
    public var fingerprints: [ShareImportFingerprint]

    public init(fingerprints: [ShareImportFingerprint]) {
        self.fingerprints = fingerprints
    }
}

public enum ShareImportCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// `records/` and `files/` under a directory the caller owns. The app group path stays out of this
/// type so the Linux domain tests can use a temporary folder.
public struct ShareImportInbox: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func enqueue(_ record: ShareImportRecord, file: URL?) throws -> ShareImportRecord {
        let records = root.appendingPathComponent("records", isDirectory: true)
        let files = root.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        var stored = record
        if let file {
            let ext = file.pathExtension.isEmpty ? "bin" : file.pathExtension
            let name = "\(record.id.uuidString).\(ext)"
            let destination = files.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: file, to: destination)
            stored.storedFileName = name
        }
        let data = try ShareImportCoding.encoder().encode(stored)
        try data.write(to: records.appendingPathComponent("\(record.id.uuidString).json"), options: .atomic)
        return stored
    }

    public func pending() throws -> [ShareImportRecord] {
        let records = root.appendingPathComponent("records", isDirectory: true)
        guard FileManager.default.fileExists(atPath: records.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: records, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
        let decoder = ShareImportCoding.decoder()
        let decoded = try urls.map { url in
            try decoder.decode(ShareImportRecord.self, from: Data(contentsOf: url))
        }
        return decoded.sorted { $0.createdAt < $1.createdAt }
    }

    public func fileURL(for record: ShareImportRecord) -> URL? {
        guard let name = record.storedFileName, !name.isEmpty else { return nil }
        let url = root.appendingPathComponent("files", isDirectory: true).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func remove(_ id: UUID) throws {
        let recordURL = root.appendingPathComponent("records", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).json")
        if let data = try? Data(contentsOf: recordURL),
           let record = try? ShareImportCoding.decoder().decode(ShareImportRecord.self, from: data),
           let name = record.storedFileName {
            try? FileManager.default.removeItem(
                at: root.appendingPathComponent("files", isDirectory: true).appendingPathComponent(name)
            )
        }
        if FileManager.default.fileExists(atPath: recordURL.path) {
            try FileManager.default.removeItem(at: recordURL)
        }
    }
}

public enum ShareImportIndexStore {
    public static func load(from root: URL) -> [ShareImportFingerprint] {
        let url = root.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url),
              let index = try? ShareImportCoding.decoder().decode(ShareImportIndex.self, from: data) else {
            return []
        }
        return index.fingerprints
    }

    public static func save(_ fingerprints: [ShareImportFingerprint], to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try ShareImportCoding.encoder().encode(ShareImportIndex(fingerprints: fingerprints))
        try data.write(to: root.appendingPathComponent("index.json"), options: .atomic)
    }
}

/// Header written into `Load.rawMessage` so a later share can see the broker and file hash
/// without a new database column.
public enum ShareImportNote {
    public static let headerMark = "[TruckoRig Share]"
    public static let bodyLimit = 16_000

    public static func compose(
        logicalTripId: String,
        broker: String,
        fileSHA256: String?,
        missing: [ShareLoadMissing],
        sourceText: String
    ) -> String {
        let missingText = missing.map(\.rawValue).joined(separator: ",")
        let file = fileSHA256?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hash = (file?.isEmpty == false) ? file! : "-"
        let body = String(sourceText.prefix(bodyLimit))
        return """
        \(headerMark)
        trip: \(oneLine(logicalTripId))
        broker: \(oneLine(broker))
        file: \(hash)
        missing: \(missingText)

        \(body)
        """
    }

    /// Logical load number, broker, and file hash recovered from a saved load.
    public static func fingerprint(storageTripId: String, rawMessage: String?) -> ShareImportFingerprint {
        guard let rawMessage, rawMessage.hasPrefix(headerMark) else {
            return ShareImportFingerprint(tripId: storageTripId, broker: "", fileSHA256: nil)
        }
        let lines = rawMessage.split(separator: "\n", maxSplits: 8, omittingEmptySubsequences: false).map(String.init)
        let trip = value("trip:", in: lines) ?? storageTripId
        let broker = value("broker:", in: lines) ?? ""
        let file = value("file:", in: lines)
        let hash = (file == nil || file == "-" || file?.isEmpty == true) ? nil : file
        return ShareImportFingerprint(tripId: trip, broker: broker, fileSHA256: hash)
    }

    private static func value(_ key: String, in lines: [String]) -> String? {
        guard let line = lines.first(where: { $0.lowercased().hasPrefix(key) }) else { return nil }
        let raw = line.split(separator: ":", maxSplits: 1).dropFirst().joined()
        return raw.trimmingCharacters(in: .whitespaces)
    }

    private static func oneLine(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ShareLoadPlan: Equatable, Sendable {
    case duplicate
    case insert(LoadDraft)
}

/// Turns an accepted share into a draft, or reports that the journal already has it.
public enum ShareLoadCommit {
    public static func storageTripId(logical: String, broker: String, taken: Set<String>) -> String {
        let base = TripID.normalize(logical)
        let used = Set(taken.map(TripID.normalize))
        if !base.isEmpty, !used.contains(base) { return base }
        let slug = brokerSlug(broker)
        let stamped = slug.isEmpty ? "\(base)-SHARE" : "\(base)-\(slug)"
        if !used.contains(stamped) { return stamped }
        var suffix = 2
        while used.contains("\(stamped)-\(suffix)") {
            suffix += 1
        }
        return "\(stamped)-\(suffix)"
    }

    public static func brokerSlug(_ broker: String) -> String {
        let scalars = broker.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let text = String(String.UnicodeScalarView(scalars))
        return String(text.prefix(12))
    }

    public static func plan(
        fields: ShareLoadFields,
        fileSHA256: String?,
        sourceText: String,
        existing: [ShareImportFingerprint],
        takenStorageIds: Set<String>,
        calendar: Calendar = .current
    ) -> ShareLoadPlan {
        let candidate = ShareImportFingerprint(tripId: fields.tripId, broker: fields.broker, fileSHA256: fileSHA256)
        if ShareImportDeduper.isDuplicate(candidate, among: existing) {
            return .duplicate
        }
        let storageId = storageTripId(logical: fields.tripId, broker: fields.broker, taken: takenStorageIds)
        let raw = ShareImportNote.compose(
            logicalTripId: fields.tripId,
            broker: fields.broker,
            fileSHA256: fileSHA256,
            missing: fields.missing,
            sourceText: sourceText
        )
        return .insert(draft(fields: fields, storageTripId: storageId, rawMessage: raw, calendar: calendar))
    }

    public static func draft(
        fields: ShareLoadFields,
        storageTripId: String,
        rawMessage: String,
        calendar: Calendar = .current
    ) -> LoadDraft {
        var stops: [StopDraft] = []
        if let pickup = placeStop(.pickup, address: fields.origin, when: fields.pickupDate, number: 1, calendar: calendar) {
            stops.append(pickup)
        }
        if let delivery = placeStop(.delivery, address: fields.destination, when: fields.deliveryDate, number: stops.count + 1, calendar: calendar) {
            stops.append(delivery)
        }
        let filed = fields.pickupDate ?? fields.deliveryDate ?? Date()
        return LoadDraft(
            tripId: storageTripId,
            date: noon(filed, calendar: calendar),
            totalRate: fields.rate,
            totalMiles: max(0, fields.miles),
            stops: stops,
            rawMessage: rawMessage
        )
    }

    private static func placeStop(
        _ type: StopType,
        address: String,
        when: Date?,
        number: Int,
        calendar: Calendar
    ) -> StopDraft? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = AddressParser.parseLine(trimmed)
        let scheduled = when.map { noon($0, calendar: calendar) }
        let day = scheduled.map {
            MediaClock.format($0, pattern: "yyyy-MM-dd", timeZone: calendar.timeZone)
        }
        return StopDraft(
            type: type,
            stopNumber: number,
            fullAddress: parts.fullAddress.isEmpty ? trimmed : parts.fullAddress,
            city: parts.city.isEmpty ? trimmed : parts.city,
            state: parts.state,
            zip: parts.zip,
            scheduledTime: scheduled,
            localDay: day,
            timezone: ""
        )
    }

    private static func noon(_ date: Date, calendar source: Calendar) -> Date {
        let calendar = source
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: DateComponents(
            year: parts.year,
            month: parts.month,
            day: parts.day,
            hour: 12
        )) ?? date
    }
}
