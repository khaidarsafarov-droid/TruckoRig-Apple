import Foundation

/// One-time move of a previous Sign in with Apple store into the single local database.
///
/// Older builds kept a separate SwiftData file per Apple user id. The app is local-only now, so
/// that file (and its photos) become the local store instead of being abandoned on upgrade.
enum LocalStoreMigration {

    private static let sessionKey = "truckorig.session"
    private static let didMigrateKey = "truckorig.didMigrateToLocalOnly"

    /// Display name captured from the old Apple session, applied once to an empty profile.
    private(set) static var inheritedDisplayName: String?

    static func adoptPreviousAccountIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: didMigrateKey) == false else { return }
        defer {
            defaults.set(true, forKey: didMigrateKey)
            defaults.removeObject(forKey: sessionKey)
        }

        guard let data = defaults.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(LegacySession.self, from: data),
              session.provider == "apple"
        else { return }

        inheritedDisplayName = session.displayName?.nonEmpty
        let previous = AccountScope.user(session.userId)
        AppLog.persistence.notice("Adopting previous Apple-scoped store as local")
        adoptFiles(from: previous)
        adoptSettings(from: previous, defaults: defaults)
    }

    private struct LegacySession: Decodable {
        var userId: String
        var provider: String
        var displayName: String?
    }

    private static func adoptFiles(from previous: AccountScope) {
        replaceStore(from: previous, to: .local)
        replaceMedia(from: previous, to: .local)
    }

    private static func replaceStore(from previous: AccountScope, to current: AccountScope) {
        guard let previousURL = try? AccountScopedContainer.storeURL(for: previous),
              FileManager.default.fileExists(atPath: previousURL.path)
        else { return }

        try? AccountScopedContainer.destroyStore(for: current)
        moveStoreFiles(from: previousURL, toScope: current)
    }

    private static func moveStoreFiles(from previousURL: URL, toScope current: AccountScope) {
        guard let currentURL = try? AccountScopedContainer.storeURL(for: current) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: previousURL.path + suffix)
            let destination = URL(fileURLWithPath: currentURL.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            do {
                try FileManager.default.moveItem(at: source, to: destination)
            } catch {
                AppLog.persistence.error("Could not move store file \(source.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func replaceMedia(from previous: AccountScope, to current: AccountScope) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let mediaRoot = documents.appendingPathComponent("Media", isDirectory: true)
        let source = mediaRoot.appendingPathComponent(previous.storeKey, isDirectory: true)
        let destination = mediaRoot.appendingPathComponent(current.storeKey, isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            AppLog.persistence.error("Could not move media directory: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func adoptSettings(from previous: AccountScope, defaults: UserDefaults) {
        let keys = ["weeklyGoal", "language", "weekStart", "rpmMinProfit", "rpmTargetProfit"]
        for key in keys {
            let sourceKey = "truckorig.\(previous.storeKey).\(key)"
            let destKey = "truckorig.\(AccountScope.local.storeKey).\(key)"
            guard let value = defaults.object(forKey: sourceKey) else { continue }
            defaults.set(value, forKey: destKey)
        }
    }
}
