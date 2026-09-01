import Foundation

enum MediaUploadError: Error, LocalizedError {
    case fileMissing
    case uploadRejected(status: Int)

    var errorDescription: String? {
        switch self {
        case .fileMissing: return String(localized: "media.error.missingFile")
        case .uploadRejected: return String(localized: "media.error.upload")
        }
    }
}

/// Uploads a photo or scan straight to object storage.
///
/// Three steps: ask the backend for a presigned destination, PUT the bytes there, then confirm.
/// The bytes never pass through the backend, and the PUT deliberately goes out on a bare
/// `URLSession` — the presigned URL carries its own signature, and attaching the account's bearer
/// token would leak it to the storage provider.
struct MediaUploader {

    let client: APIClient
    let store: MediaStore
    let session: URLSession

    init(client: APIClient, store: MediaStore, session: URLSession = .shared) {
        self.client = client
        self.store = store
        self.session = session
    }

    /// Uploads one file and returns the object key the backend assigned.
    func upload(
        fileName: String,
        kind: MediaStore.Kind,
        entityType: SyncEntityType,
        entityId: UUID
    ) async throws -> String {
        guard let url = store.url(for: fileName, kind: kind),
              FileManager.default.fileExists(atPath: url.path)
        else { throw MediaUploadError.fileMissing }

        let data = try Data(contentsOf: url)
        let ticket = try await client.send(
            Endpoints.mediaUploadURL(
                MediaUploadRequest(
                    fileName: fileName,
                    contentType: "image/jpeg",
                    byteSize: data.count,
                    kind: kind.rawValue
                )
            ),
            as: MediaUploadTicket.self
        )

        try await put(data, to: ticket)

        try await client.send(
            Endpoints.mediaComplete(
                MediaCompleteRequest(
                    objectKey: ticket.objectKey,
                    entityType: entityType.rawValue,
                    entityId: entityId.uuidString
                )
            )
        )
        return ticket.objectKey
    }

    private func put(_ data: Data, to ticket: MediaUploadTicket) async throws {
        var request = URLRequest(url: ticket.uploadURL)
        request.httpMethod = HTTPMethod.put.rawValue
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        for (field, value) in ticket.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: field)
        }
        // Uploads run on a phone in a truck; give them longer than an API call.
        request.timeoutInterval = 120

        let (_, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Log the destination without its signature.
            AppLog.media.error("Upload rejected by \(AppLog.redact(ticket.uploadURL), privacy: .public)")
            throw MediaUploadError.uploadRejected(status: http.statusCode)
        }
    }
}
