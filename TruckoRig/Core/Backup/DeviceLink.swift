import Foundation
import Network
import Observation

/// Whether this phone can reach Telegram and iCloud. The journal does not use it.
@MainActor
@Observable
final class DeviceLink {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "truckorig.link"))
    }
}
