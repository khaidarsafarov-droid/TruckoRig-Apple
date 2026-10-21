import Foundation

/// Flash cycle from Android `CameraFlashMode`: off → auto → on → off.
public enum CameraFlashMode: String, Equatable, Sendable, CaseIterable {
    case off
    case auto
    case on

    public var next: CameraFlashMode {
        switch self {
        case .off: return .auto
        case .auto: return .on
        case .on: return .off
        }
    }
}

/// Which load a camera session should attach to. Port of `CameraAttachContext`.
public struct CameraAttachContext: Equatable, Sendable {
    public var loadId: String?
    public var tripId: String?
    public var loadDate: String?

    public init(loadId: String?, tripId: String?, loadDate: String?) {
        self.loadId = loadId
        self.tripId = tripId
        self.loadDate = loadDate
    }

    public static func fromExplicit(
        attachLoadId: String?,
        attachTripId: String?,
        attachLoadDate: String?
    ) -> CameraAttachContext? {
        let loadId = blankToNil(attachLoadId)
        let tripId = blankToNil(attachTripId)
        if loadId == nil && tripId == nil { return nil }
        return CameraAttachContext(
            loadId: loadId,
            tripId: tripId,
            loadDate: blankToNil(attachLoadDate)
        )
    }

    /// Free camera (drawer): watermark with the latest Trip ID, do not auto-attach.
    public static func fromLatestLoad(
        loadId: String?,
        tripId: String?,
        loadDate: String?
    ) -> CameraAttachContext {
        CameraAttachContext(
            loadId: blankToNil(loadId),
            tripId: blankToNil(tripId),
            loadDate: blankToNil(loadDate)
        )
    }

    public var isAttachedToLoad: Bool { loadId != nil }

    private static func blankToNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Naming, watermark lines, and the photo row. Port of `PhotoManager` plus `PhotoRepository.savePhoto`.
public enum PhotoCapture {
    public static let jpegQuality = 90
    public static let maxEdgePixels = 2048
    public static let directoryName = "photos"
    public static let unknownLabel = "Неизвестно"
    public static let appName = "TruckoRig"

    /// Power-of-two decode sample so the longer edge stays near `targetEdge`.
    /// Port of Android `computeInSampleSize`.
    public static func sampleSize(width: Int, height: Int, targetEdge: Int = maxEdgePixels) -> Int {
        if width <= 0 || height <= 0 || targetEdge <= 0 { return 1 }
        var sample = 1
        let halfWidth = width / 2
        let halfHeight = height / 2
        while halfWidth / sample >= targetEdge && halfHeight / sample >= targetEdge {
            sample *= 2
        }
        while max(width, height) / sample > targetEdge * 2 {
            sample *= 2
        }
        return max(sample, 1)
    }

    public static func sampleSize(longEdge: Int, targetEdge: Int = maxEdgePixels) -> Int {
        sampleSize(width: longEdge, height: longEdge, targetEdge: targetEdge)
    }

    public static func resolveWatermarkTitle(
        watermarkTitle: String?,
        tripId: String?,
        fallback: String
    ) -> String {
        if let watermarkTitle, !watermarkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return watermarkTitle
        }
        if let tripId, !tripId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return tripId
        }
        return fallback
    }

    public static func resolveGpsWatermarkLine(
        hasCoordinates: Bool,
        coordinatesLine: String,
        unknownLabel: String
    ) -> String {
        hasCoordinates ? coordinatesLine : unknownLabel
    }

    public static func watermarkLines(
        title: String?,
        tripId: String?,
        timestamp: Date,
        location: LocationStamp,
        unknownLabel: String = PhotoCapture.unknownLabel,
        fallbackTitle: String = PhotoCapture.appName,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> [String] {
        let header = resolveWatermarkTitle(watermarkTitle: title, tripId: tripId, fallback: fallbackTitle)
        let dateLine = MediaClock.format(timestamp, pattern: "dd.MM.yyyy HH:mm", timeZone: timeZone, locale: locale)
        // `cityStateLine` is "—" when both city and state are blank, and "—" is not blank,
        // so Android keeps the dash. ZIP and GPS still fall back to the unknown label.
        let place = location.cityStateLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? unknownLabel
            : location.cityStateLine
        let zip = location.zipCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? unknownLabel
            : location.zipCode
        let gps = resolveGpsWatermarkLine(
            hasCoordinates: location.hasCoordinates,
            coordinatesLine: location.coordinatesLine,
            unknownLabel: unknownLabel
        )
        return [header, dateLine, place, zip, gps]
    }

    public static func fileName(
        tripId: String?,
        loadDate: String?,
        timestamp: Date,
        timeZone: TimeZone = .current
    ) -> String {
        if let tripId, !tripId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AttachmentNaming.buildFileName(
                tripId: tripId,
                loadDate: loadDate ?? "",
                timestamp: timestamp,
                extension: "jpg",
                timeZone: timeZone
            )
        }
        let stamp = MediaClock.format(timestamp, pattern: "yyyyMMdd_HHmmss", timeZone: timeZone)
        return "photo_\(stamp)_\(MediaClock.epochMillis(timestamp)).jpg"
    }

    public static func relativePath(fileName: String) -> String {
        "\(directoryName)/\(fileName)"
    }

    /// Asks for a discard confirmation only when a photo was already written onto a load.
    public static func needsDiscardConfirmation(anySavedToDatabase: Bool, attachedToLoad: Bool) -> Bool {
        anySavedToDatabase && attachedToLoad
    }
}

/// Columns written to the photo table. Cloud-sync columns from Room are omitted on purpose.
public struct StoredPhotoFields: Equatable, Sendable {
    public var fileName: String
    public var filePath: String
    public var latitude: Double
    public var longitude: Double
    public var city: String
    public var state: String
    public var zipCode: String
    public var timestampMillis: Int64
    public var loadId: String?

    public init(
        fileName: String,
        filePath: String,
        latitude: Double,
        longitude: Double,
        city: String,
        state: String,
        zipCode: String,
        timestampMillis: Int64,
        loadId: String?
    ) {
        self.fileName = fileName
        self.filePath = filePath
        self.latitude = latitude
        self.longitude = longitude
        self.city = city
        self.state = state
        self.zipCode = zipCode
        self.timestampMillis = timestampMillis
        self.loadId = loadId
    }

    public static func make(
        tripId: String?,
        loadDate: String?,
        location: LocationStamp,
        timestamp: Date,
        loadId: String?,
        timeZone: TimeZone = .current
    ) -> StoredPhotoFields {
        let name = PhotoCapture.fileName(
            tripId: tripId,
            loadDate: loadDate,
            timestamp: timestamp,
            timeZone: timeZone
        )
        return StoredPhotoFields(
            fileName: name,
            filePath: PhotoCapture.relativePath(fileName: name),
            latitude: location.persistedLatitude,
            longitude: location.persistedLongitude,
            city: location.city,
            state: location.state,
            zipCode: location.zipCode,
            timestampMillis: MediaClock.epochMillis(timestamp),
            loadId: loadId
        )
    }
}

/// Place line on the photo detail screen: `"${city}, ${state} ${zip}".trim()`.
public enum PhotoMetadataDisplay {
    public static func placeLine(city: String, state: String, zipCode: String) -> String {
        "\(city), \(state) \(zipCode)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func coordinateLine(latitude: Double, longitude: Double) -> String {
        "\(latitude), \(longitude)"
    }

    public static func dateLine(timestamp: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        MediaClock.format(timestamp, pattern: "dd.MM.yyyy HH:mm", timeZone: timeZone, locale: locale)
    }
}
