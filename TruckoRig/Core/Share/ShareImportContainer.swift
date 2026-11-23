import Foundation

/// App Group folder the share extension writes and the app reads on the next foreground.
enum ShareImportContainer {
    static func rootURL() -> URL? {
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ShareImportLocation.appGroupIdentifier
        ) else {
            return nil
        }
        let url = base.appendingPathComponent("ShareInbox", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return url
    }

    static func inbox() -> ShareImportInbox? {
        guard let root = rootURL() else { return nil }
        return ShareImportInbox(root: root)
    }
}
