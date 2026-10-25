import Foundation

/// Photos and scans next to the Android v2 JSON file. The journal schema does not change.
///
/// Files live in `Documents/Media/<account>/photos` and `.../scans`. `manifest.json` in that
/// folder is the only link between a file and a load. Android never reads it. iCloud is not
/// asked to delete anything: a file removed on this phone stays in the folder and in the
/// manifest until the driver deletes it in the Files app. A later restore downloads it again.
public enum ICloudMediaPolicy {
    public static let folderName = "Media"
    public static let manifestFileName = "manifest.json"
    public static let manifestKind = "truckorig-media"
    public static let manifestVersion = 1
    public static let backgroundTaskIdentifier = "com.truckorig.icloud-media"
    public static let photoDirectory = "photos"
    public static let scanDirectory = "scans"
    public static let mediaEnabledByDefault = true
    public static let wifiOnlyByDefault = true
    /// Heavy uploads wait for a plugged-in `BGProcessingTask`. Two minutes batches a burst of shots.
    public static let backgroundDelayAfterChange: TimeInterval = 2 * 60
    public static let backgroundRetryDelay: TimeInterval = 15 * 60
    /// One scan is capped well above a 20-page PDF. Larger files stay on the phone.
    public static let maxFileBytes: Int64 = 80 * 1024 * 1024

    /// The app has no automatic delete. Locked by tests.
    public static let allowsAutomaticDeletion = false

    public static let deletionRule =
        "TruckoRig never deletes a photo or scan from iCloud. Removing it on this phone does not remove the copy. The bytes stay in Media/<account>/ and the manifest keeps the row. Restore downloads that file again. The copy leaves iCloud only when you delete it yourself in the Files app. The next sync then drops it, because it is neither on the phone nor still in iCloud."

    public enum Kind {
        public static let photo = "photo"
        public static let scan = "scan"
    }

    public struct Item: Equatable, Sendable {
        public var recordId: String
        public var kind: String
        public var fileName: String
        public var relativePath: String
        public var contentHash: String
        public var byteCount: Int64
        public var modifiedAt: Int64
        public var loadId: String?
        public var tripId: String?
        public var latitude: Double?
        public var longitude: Double?
        public var city: String
        public var state: String
        public var zipCode: String
        public var timestampMillis: Int64
        public var caption: String?
        public var ocrText: String?
        public var title: String?
        public var pageCount: Int
        public var category: String

        public init(
            recordId: String,
            kind: String,
            fileName: String,
            relativePath: String = "",
            contentHash: String = "",
            byteCount: Int64 = 0,
            modifiedAt: Int64 = 0,
            loadId: String? = nil,
            tripId: String? = nil,
            latitude: Double? = nil,
            longitude: Double? = nil,
            city: String = "",
            state: String = "",
            zipCode: String = "",
            timestampMillis: Int64 = 0,
            caption: String? = nil,
            ocrText: String? = nil,
            title: String? = nil,
            pageCount: Int = 0,
            category: String = ""
        ) {
            self.recordId = recordId
            self.kind = kind
            self.fileName = fileName
            self.relativePath = relativePath
            self.contentHash = contentHash
            self.byteCount = byteCount
            self.modifiedAt = modifiedAt
            self.loadId = loadId
            self.tripId = tripId
            self.latitude = latitude
            self.longitude = longitude
            self.city = city
            self.state = state
            self.zipCode = zipCode
            self.timestampMillis = timestampMillis
            self.caption = caption
            self.ocrText = ocrText
            self.title = title
            self.pageCount = pageCount
            self.category = category
        }
    }

    public struct Manifest: Equatable, Sendable {
        public var accountId: String
        public var updatedAt: Int64
        public var items: [Item]

        public init(accountId: String, updatedAt: Int64, items: [Item]) {
            self.accountId = accountId
            self.updatedAt = updatedAt
            self.items = items
        }
    }

    public enum ManifestError: Error, Equatable, Sendable {
        case invalid
        case unsupported(Int)
    }

    public struct Plan: Equatable, Sendable {
        public var upload: [Item]
        public var manifestOnly: [Item]
        public var unchanged: [Item]
        public var retained: [Item]
        public var manifestItems: [Item]
        /// Always empty. Local deletion does not become a cloud deletion.
        public var deletions: [String]
        public var rewritesManifest: Bool
    }

    public struct Progress: Equatable, Sendable {
        public var completed: Int
        public var total: Int
        public var unavailable: Int

        public init(completed: Int, total: Int, unavailable: Int) {
            self.completed = completed
            self.total = total
            self.unavailable = unavailable
        }
    }

    public struct Conditions: Equatable, Sendable {
        public var availability: ICloudBackupPolicy.Availability
        public var mediaEnabled: Bool
        public var wifiOnly: Bool
        public var onWifi: Bool
        public var lowPowerMode: Bool
        public var userRequested: Bool
        public var backgroundTask: Bool

        public init(
            availability: ICloudBackupPolicy.Availability,
            mediaEnabled: Bool,
            wifiOnly: Bool,
            onWifi: Bool,
            lowPowerMode: Bool,
            userRequested: Bool,
            backgroundTask: Bool
        ) {
            self.availability = availability
            self.mediaEnabled = mediaEnabled
            self.wifiOnly = wifiOnly
            self.onWifi = onWifi
            self.lowPowerMode = lowPowerMode
            self.userRequested = userRequested
            self.backgroundTask = backgroundTask
        }
    }

    public enum Gate: Equatable, Sendable {
        /// Upload in this process. Foreground only when the driver asked and the device can take it.
        case uploadNow
        /// Leave the bytes for `BGProcessingTask` (charging, and Wi-Fi when that switch is on).
        case deferToBackground
        case skipWifi
        case skipLowPower
        case skipDisabled
        case unavailable
    }

    public static func contentHash(_ bytes: [UInt8]) -> String {
        TelegramSHA256.hex(bytes)
    }

    public static func totalBytes(_ items: [Item]) -> Int64 {
        items.reduce(0) { $0 + max(0, $1.byteCount) }
    }

    /// `photos/name.jpg` or `scans/name.pdf`. Rejects `..` and any nested folder.
    public static func canonicalRelativePath(kind: String, fileName: String) -> String? {
        let folder: String
        switch kind {
        case Kind.photo: folder = photoDirectory
        case Kind.scan: folder = scanDirectory
        default: return nil
        }
        guard let base = sanitizedBase(fileName) else { return nil }
        return "\(folder)/\(base)"
    }

    public static func normalizedCoordinate(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return (value * 1_000_000).rounded() / 1_000_000
    }

    /// Bot tokens, key names, and (for JSON text) API keys and JWTs.
    public static func fileIsSecret(_ bytes: [UInt8]) -> Bool {
        guard !bytes.isEmpty, let text = String(bytes: bytes, encoding: .isoLatin1) else { return false }
        if text.range(of: #"\d{5,16}:[A-Za-z0-9_-]{20,}"#, options: .regularExpression) != nil {
            return true
        }
        let lowered = text.lowercased()
        return lowered.contains("\"bottoken\"")
            || lowered.contains("\"passphrase\"")
            || lowered.contains("\"telegramtoken\"")
    }

    public static func documentIsSecret(_ bytes: [UInt8]) -> Bool {
        if fileIsSecret(bytes) { return true }
        guard let text = String(bytes: bytes, encoding: .utf8) else { return false }
        if text.range(of: #"AIza[0-9A-Za-z_\-]{20,}"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    public static func redactBackupText(_ raw: String) -> String {
        var text = TelegramRedactor.redact(raw)
        text = replace(text, #"\d{5,16}:[A-Za-z0-9_-]{20,}"#, "***")
        text = replace(text, #"AIza[0-9A-Za-z_\-]{20,}"#, "***")
        text = replace(text, #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#, "***")
        return text
    }

    public static func gate(_ conditions: Conditions) -> Gate {
        if conditions.availability != .available { return .unavailable }
        if !conditions.mediaEnabled { return .skipDisabled }
        if conditions.backgroundTask {
            if conditions.lowPowerMode { return .skipLowPower }
            if conditions.wifiOnly && !conditions.onWifi { return .skipWifi }
            return .uploadNow
        }
        if conditions.userRequested {
            if conditions.lowPowerMode { return .deferToBackground }
            if conditions.wifiOnly && !conditions.onWifi { return .skipWifi }
            return .uploadNow
        }
        return .deferToBackground
    }

    /// New and changed files upload. Same hash skips the bytes. Remote-only rows are kept.
    public static func plan(local: [Item], remote: [Item]) -> Plan {
        let locals = deduped(local.compactMap(sanitize))
        let remotes = deduped(remote.compactMap(sanitize))
        let remoteByPath = Dictionary(uniqueKeysWithValues: remotes.map { ($0.relativePath, $0) })
        var upload: [Item] = []
        var manifestOnly: [Item] = []
        var unchanged: [Item] = []
        var localPaths = Set<String>()

        for item in locals {
            localPaths.insert(item.relativePath)
            guard let existing = remoteByPath[item.relativePath] else {
                upload.append(item)
                continue
            }
            if sameBytes(item, existing) {
                if sameDescription(item, existing) {
                    unchanged.append(existing)
                } else {
                    var updated = item
                    updated.contentHash = existing.contentHash.isEmpty ? item.contentHash : existing.contentHash
                    updated.byteCount = existing.byteCount > 0 ? existing.byteCount : item.byteCount
                    manifestOnly.append(updated)
                }
            } else {
                upload.append(item)
            }
        }

        let retained = remotes.filter { !localPaths.contains($0.relativePath) }
        let manifestItems = deduped(upload + manifestOnly + unchanged + retained)
        let rewrites = signature(remotes) != signature(manifestItems)
        return Plan(
            upload: upload,
            manifestOnly: manifestOnly,
            unchanged: unchanged,
            retained: retained,
            manifestItems: manifestItems,
            deletions: [],
            rewritesManifest: rewrites
        )
    }

    public static func restorePartition(
        items: [Item],
        availableRelativePaths: Set<String>
    ) -> (ready: [Item], unavailable: [Item]) {
        var ready: [Item] = []
        var unavailable: [Item] = []
        for item in items {
            if availableRelativePaths.contains(item.relativePath) {
                ready.append(item)
            } else {
                unavailable.append(item)
            }
        }
        return (ready, unavailable)
    }

    public static func encode(_ manifest: Manifest) -> String {
        let clean = manifest.items.compactMap(sanitize)
        let body: [String: Any] = [
            "kind": manifestKind,
            "manifestVersion": NSNumber(value: manifestVersion),
            "accountId": manifest.accountId,
            "updatedAt": NSNumber(value: manifest.updatedAt),
            "items": clean.map(jsonObject),
        ]
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(
                withJSONObject: body,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let text = String(data: data, encoding: .utf8),
              !documentIsSecret(Array(text.utf8))
        else { return "" }
        return text
    }

    public static func decode(_ json: String) throws -> Manifest {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else { throw ManifestError.invalid }
        guard (root["kind"] as? String) == manifestKind else { throw ManifestError.invalid }
        let version = int(root["manifestVersion"]) ?? 0
        if version > manifestVersion { throw ManifestError.unsupported(version) }
        guard version == manifestVersion else { throw ManifestError.invalid }
        let rows = root["items"] as? [Any] ?? []
        let items = rows.compactMap { value -> Item? in
            guard let row = value as? [String: Any] else { return nil }
            return sanitize(item(from: row))
        }
        return Manifest(
            accountId: string(root["accountId"]) ?? "",
            updatedAt: int64(root["updatedAt"]) ?? 0,
            items: deduped(items)
        )
    }

    // MARK: - Private

    private static func sanitize(_ item: Item) -> Item? {
        let record = item.recordId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !record.isEmpty, !fileIsSecret(Array(record.utf8)) else { return nil }
        guard let relative = canonicalRelativePath(kind: item.kind, fileName: item.fileName) else { return nil }
        guard item.byteCount <= maxFileBytes else { return nil }
        var copy = item
        copy.recordId = record
        copy.relativePath = relative
        copy.fileName = relative.split(separator: "/").last.map(String.init) ?? item.fileName
        copy.loadId = blankToNil(item.loadId.map(redactBackupText))
        copy.tripId = blankToNil(item.tripId.map(redactBackupText))
        copy.latitude = normalizedCoordinate(item.latitude)
        copy.longitude = normalizedCoordinate(item.longitude)
        copy.city = redactBackupText(item.city)
        copy.state = redactBackupText(item.state)
        copy.zipCode = redactBackupText(item.zipCode)
        copy.caption = blankToNil(item.caption.map(redactBackupText))
        copy.ocrText = blankToNil(item.ocrText.map(redactBackupText))
        copy.title = blankToNil(item.title.map(redactBackupText))
        copy.category = redactBackupText(item.category)
        return copy
    }

    private static func sameBytes(_ local: Item, _ remote: Item) -> Bool {
        if !local.contentHash.isEmpty, local.contentHash == remote.contentHash { return true }
        if local.contentHash.isEmpty || remote.contentHash.isEmpty {
            return local.byteCount > 0
                && local.byteCount == remote.byteCount
                && local.modifiedAt == remote.modifiedAt
        }
        return false
    }

    private static func sameDescription(_ local: Item, _ remote: Item) -> Bool {
        local.recordId == remote.recordId
            && local.kind == remote.kind
            && local.fileName == remote.fileName
            && local.loadId == remote.loadId
            && local.tripId == remote.tripId
            && local.latitude == remote.latitude
            && local.longitude == remote.longitude
            && local.city == remote.city
            && local.state == remote.state
            && local.zipCode == remote.zipCode
            && local.timestampMillis == remote.timestampMillis
            && local.caption == remote.caption
            && local.ocrText == remote.ocrText
            && local.title == remote.title
            && local.pageCount == remote.pageCount
            && local.category == remote.category
    }

    private static func signature(_ items: [Item]) -> [String] {
        items.map(signature(of:)).sorted()
    }

    private static func signature(of item: Item) -> String {
        let latitude = coordinateText(item.latitude)
        let longitude = coordinateText(item.longitude)
        let parts = [
            item.relativePath,
            item.recordId,
            item.kind,
            item.fileName,
            item.contentHash,
            String(item.byteCount),
            String(item.modifiedAt),
            item.loadId ?? "",
            item.tripId ?? "",
            latitude,
            longitude,
            item.city,
            item.state,
            item.zipCode,
            String(item.timestampMillis),
            item.caption ?? "",
            item.ocrText ?? "",
            item.title ?? "",
            String(item.pageCount),
            item.category,
        ]
        return parts.joined(separator: "\u{1f}")
    }

    private static func coordinateText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private static func deduped(_ items: [Item]) -> [Item] {
        var best: [String: Item] = [:]
        for item in items {
            if let existing = best[item.relativePath] {
                if item.modifiedAt >= existing.modifiedAt {
                    best[item.relativePath] = item
                }
            } else {
                best[item.relativePath] = item
            }
        }
        return best.values.sorted { $0.relativePath < $1.relativePath }
    }

    private static func jsonObject(_ item: Item) -> [String: Any] {
        var row: [String: Any] = [
            "recordId": item.recordId,
            "kind": item.kind,
            "fileName": item.fileName,
            "relativePath": item.relativePath,
            "contentHash": item.contentHash,
            "byteCount": NSNumber(value: item.byteCount),
            "modifiedAt": NSNumber(value: item.modifiedAt),
            "city": item.city,
            "state": item.state,
            "zipCode": item.zipCode,
            "timestampMillis": NSNumber(value: item.timestampMillis),
            "pageCount": NSNumber(value: item.pageCount),
            "category": item.category,
        ]
        if let loadId = item.loadId { row["loadId"] = loadId }
        if let tripId = item.tripId { row["tripId"] = tripId }
        if let latitude = item.latitude { row["latitude"] = NSNumber(value: latitude) }
        if let longitude = item.longitude { row["longitude"] = NSNumber(value: longitude) }
        if let caption = item.caption { row["caption"] = caption }
        if let ocrText = item.ocrText { row["ocrText"] = ocrText }
        if let title = item.title { row["title"] = title }
        return row
    }

    private static func item(from row: [String: Any]) -> Item {
        Item(
            recordId: string(row["recordId"]) ?? "",
            kind: string(row["kind"]) ?? "",
            fileName: string(row["fileName"]) ?? "",
            relativePath: string(row["relativePath"]) ?? "",
            contentHash: string(row["contentHash"]) ?? "",
            byteCount: int64(row["byteCount"]) ?? 0,
            modifiedAt: int64(row["modifiedAt"]) ?? 0,
            loadId: string(row["loadId"]),
            tripId: string(row["tripId"]),
            latitude: double(row["latitude"]),
            longitude: double(row["longitude"]),
            city: string(row["city"]) ?? "",
            state: string(row["state"]) ?? "",
            zipCode: string(row["zipCode"]) ?? "",
            timestampMillis: int64(row["timestampMillis"]) ?? 0,
            caption: string(row["caption"]),
            ocrText: string(row["ocrText"]),
            title: string(row["title"]),
            pageCount: int(row["pageCount"]) ?? 0,
            category: string(row["category"]) ?? ""
        )
    }

    private static func sanitizedBase(_ name: String) -> String? {
        let slash = name.replacingOccurrences(of: "\\", with: "/")
        let base = slash.split(separator: "/").last.map(String.init) ?? ""
        if base.isEmpty || base == "." || base == ".." { return nil }
        if base.utf8.count > 180 { return nil }
        if base.unicodeScalars.contains(where: { $0.value < 32 }) { return nil }
        return base
    }

    private static func blankToNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func string(_ value: Any?) -> String? {
        if value == nil || value is NSNull { return nil }
        guard let text = value as? String else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static func int(_ value: Any?) -> Int? {
        guard let number = int64(value) else { return nil }
        return Int(number)
    }

    private static func int64(_ value: Any?) -> Int64? {
        if value == nil || value is NSNull { return nil }
        if let number = value as? NSNumber { return number.int64Value }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if value == nil || value is NSNull { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}
