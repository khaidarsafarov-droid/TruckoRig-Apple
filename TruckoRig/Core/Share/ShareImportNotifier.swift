import Foundation

/// Cross-process ping. The extension posts it after writing the inbox. The app imports if it is
/// already running. A suspended app does not wake; `scenePhase == .active` covers that case.
final class ShareImportNotifier: @unchecked Sendable {
    static let shared = ShareImportNotifier()

    var onImport: (@Sendable () -> Void)?

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let notifier = Unmanaged<ShareImportNotifier>.fromOpaque(observer).takeUnretainedValue()
                notifier.deliver()
            },
            ShareImportLocation.darwinNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(ShareImportLocation.darwinNotification as CFString),
            nil,
            nil,
            true
        )
    }

    private func deliver() {
        let callback = onImport
        DispatchQueue.main.async {
            callback?()
        }
    }
}
