import Foundation
import BackgroundTasks

/// Android `DriveSyncWorker`: one periodic job, 12 hours, network required, keep the existing request.
enum DriveBackgroundRegistrar {
    static let identifier = DriveSchedule.taskIdentifier
    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task { @MainActor in
                let ok = await DriveRuntime.runPeriodic()
                task.setTaskCompleted(success: ok)
                submit(replace: true)
            }
            task.expirationHandler = {
                work.cancel()
                task.setTaskCompleted(success: false)
                submit(replace: true)
            }
        }
    }

    /// `replace == false` keeps a pending request, matching `ExistingPeriodicWorkPolicy.KEEP`.
    static func submit(replace: Bool) {
        let identifier = identifier
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            if !replace && requests.contains(where: { $0.identifier == identifier }) {
                return
            }
            let request = BGProcessingTaskRequest(identifier: identifier)
            request.requiresNetworkConnectivity = DriveSchedule.requiresNetwork
            request.requiresExternalPower = DriveSchedule.requiresExternalPower
            request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(DriveSchedule.periodicIntervalSeconds))
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                // The system rejects a second pending request or a missing identifier. The next
                // foreground launch submits again.
            }
        }
    }
}

enum DriveRuntime {
    @MainActor static weak var coordinator: DriveCoordinator?

    @MainActor
    static func runPeriodic() async -> Bool {
        if let coordinator {
            return await coordinator.runPeriodic()
        }
        let settings = AppSettings(scope: .local)
        let persistence = PersistenceController(scope: .local)
        let coordinator = DriveCoordinator(
            database: persistence.database,
            settings: settings,
            media: MediaStore(scope: .local)
        )
        return await coordinator.runPeriodic()
    }
}
