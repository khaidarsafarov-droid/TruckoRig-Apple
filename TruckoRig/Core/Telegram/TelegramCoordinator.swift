import BackgroundTasks
import Foundation
import Observation

/// Starts and stops the on-device long poll. The bot runs while TruckoRig is open.
@MainActor
@Observable
final class TelegramCoordinator {
    private let database: AppDatabase
    private let settings: AppSettings
    private let prefs: TelegramPrefs
    private let tokens: TelegramTokenStore
    private let session = TelegramSession()
    private var poll: Task<Void, Never>?

    var isPremium: () -> Bool = { false }
    var onJournalChanged: (() -> Void)?

    private(set) var hasToken = false
    private(set) var listening = false
    private(set) var paired = false
    private(set) var pairingCode = ""
    private(set) var username: String?
    private(set) var statusMessage: String?
    private(set) var busy = false

    init(database: AppDatabase, settings: AppSettings, scope: AccountScope = .local) {
        self.database = database
        self.settings = settings
        self.prefs = TelegramPrefs(scope: scope)
        self.tokens = TelegramTokenStore(account: scope.storeKey)
        refreshLocal()
    }

    func launch() {
        refreshLocal()
        resume()
    }

    func resume() {
        refreshLocal()
        // Android starts the poller when a token is saved. Premium gates the Settings screen, not the poller.
        guard hasToken else {
            pause()
            return
        }
        guard poll == nil else {
            listening = true
            return
        }
        listening = true
        poll = Task { [weak self] in
            await self?.loop()
        }
    }

    func pause() {
        poll?.cancel()
        poll = nil
        listening = false
    }

    /// Pull to refresh. Returns the Android toast when a token is saved.
    func pullToRefresh() async -> String? {
        refreshLocal()
        guard hasToken, let token = try? tokens.read() else { return nil }
        let engine = makeEngine()
        _ = await engine.catchUp(token: token)
        resume()
        return String(localized: "journal.telegram.syncStarted")
    }

    func catchUpInBackground() async -> Bool {
        refreshLocal()
        guard let token = try? tokens.read(), !token.isEmpty else { return false }
        let engine = makeEngine()
        let outcome = await engine.catchUp(token: token)
        return !outcome.stop
    }

    func saveToken(_ raw: String) async -> String? {
        let token = TelegramTokenRules.normalized(raw)
        if token.isEmpty { return String(localized: "settings.telegram.missing") }
        if !TelegramTokenRules.isPlausible(token) { return String(localized: "settings.telegram.invalid") }
        busy = true
        defer { busy = false }
        let health = await health(token)
        if health.unauthorized || !health.ok {
            return health.unauthorized ? String(localized: "settings.telegram.invalid") : (health.error ?? String(localized: "settings.telegram.invalid"))
        }
        do {
            try tokens.write(token)
        } catch {
            return String(localized: "settings.telegram.secure")
        }
        hasToken = true
        username = health.username
        let engine = makeEngine()
        await engine.applyBranding(token: token, forceName: true)
        statusMessage = String(localized: "settings.telegram.saved")
        resume()
        return nil
    }

    func testToken() async {
        guard let token = try? tokens.read() else {
            hasToken = false
            statusMessage = String(localized: "settings.telegram.missing")
            return
        }
        busy = true
        defer { busy = false }
        statusMessage = String(localized: "settings.telegram.checking")
        let health = await health(token)
        if health.ok {
            username = health.username
            statusMessage = String(localized: "settings.telegram.ok \(health.username ?? "")")
            resume()
        } else if health.unauthorized {
            statusMessage = String(localized: "settings.telegram.invalid")
            pause()
        } else {
            statusMessage = health.error ?? String(localized: "settings.telegram.invalid")
        }
    }

    func unpair() {
        prefs.clearPairing()
        refreshLocal()
        statusMessage = String(localized: "settings.telegram.unpaired")
    }

    func refreshUsername() async {
        guard username == nil || username?.isEmpty == true, let token = try? tokens.read() else { return }
        let health = await health(token)
        if health.ok { username = health.username }
    }

    func openBotURL() -> URL? {
        guard let username, !username.isEmpty else { return nil }
        let code = prefs.ensurePairingCode()
        pairingCode = code
        return URL(string: "https://t.me/\(username)?start=\(code)")
    }

    func ensureCode() -> String {
        let code = prefs.ensurePairingCode()
        pairingCode = code
        return code
    }

    private func loop() async {
        guard let token = try? tokens.read() else {
            listening = false
            poll = nil
            return
        }
        let engine = makeEngine()
        await engine.applyBranding(token: token, forceName: false)
        var attempt = 0
        while !Task.isCancelled {
            let outcome = await engine.runOnce(token: token)
            if outcome.stop {
                statusMessage = String(localized: "settings.telegram.invalid")
                break
            }
            if outcome.failed {
                let delay = TelegramSyncRules.backoffDelayMs(attemptIndex: attempt)
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            } else {
                attempt = 0
                await Task.yield()
            }
        }
        listening = false
        poll = nil
    }

    private func health(_ token: String) async -> TelegramHealth {
        guard let response = try? await session.send(TelegramBotAPI.getMe(token)) else {
            return TelegramHealth(ok: false, username: nil, unauthorized: false, error: TelegramRedactor.redact("Network error"))
        }
        return TelegramHealth.parse(status: response.status, body: response.body)
    }

    private func makeEngine() -> TelegramEngine {
        let engine = TelegramEngine(database: database, settings: settings, prefs: prefs, session: session)
        engine.onJournalChanged = { [weak self] in self?.onJournalChanged?() }
        engine.onStateChanged = { [weak self] in self?.refreshLocal() }
        return engine
    }

    func refresh() { refreshLocal() }

    private func refreshLocal() {
        hasToken = (try? tokens.read()) != nil
        paired = prefs.chatId != nil
        pairingCode = paired ? "" : prefs.ensurePairingCode()
        listening = poll != nil
    }
}

enum TelegramBackgroundRegistrar {
    static let identifier = "com.truckorig.telegram-sync"
    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task { @MainActor in
                let ok = await TelegramRuntime.catchUp()
                task.setTaskCompleted(success: ok)
                submit()
            }
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    static func submit() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

enum TelegramRuntime {
    @MainActor static weak var coordinator: TelegramCoordinator?

    @MainActor
    static func catchUp() async -> Bool {
        if let coordinator { return await coordinator.catchUpInBackground() }
        return false
    }
}
