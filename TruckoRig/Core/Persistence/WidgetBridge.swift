import Foundation
import WidgetKit

/// The few numbers the home-screen widget needs.
struct WidgetGoalSnapshot: Codable, Equatable {
    var target: Double
    var gross: Double
    var dailyTargetNeeded: Double
    var daysRemaining: Int
    var paceStatus: String
    var weekLabel: String
    var updatedAt: Date

    static let placeholder = WidgetGoalSnapshot(
        target: 6000,
        gross: 3820,
        dailyTargetNeeded: 545,
        daysRemaining: 4,
        paceStatus: PaceStatus.onTrack.rawValue,
        weekLabel: "Aug 3 – Aug 9",
        updatedAt: Date()
    )

    var progressFraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, gross / target))
    }

    var status: PaceStatus {
        PaceStatus(rawValue: paceStatus) ?? .behind
    }
}

/// Hands the widget its data through the shared App Group.
///
/// The widget process cannot open the app's SwiftData store, and account-scoped stores make that
/// worse, so the app publishes a tiny read-only snapshot instead. Nothing identifying goes in it.
enum WidgetBridge {

    static let appGroup = "group.com.truckorig"
    private static let fileName = "widget-goal.json"
    static let kind = "TruckoRigWeeklyGoal"

    /// The widget target compiles this file too, so the coders stay local rather than pulling the
    /// whole networking layer into the extension.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func publish(_ progress: WeeklyGoalProgress) {
        let snapshot = WidgetGoalSnapshot(
            target: progress.targetAmount,
            gross: progress.currentGross,
            dailyTargetNeeded: progress.dailyTargetNeeded,
            daysRemaining: progress.daysRemainingInWeek,
            paceStatus: progress.paceStatus.rawValue,
            weekLabel: progress.weekLabel,
            updatedAt: Date()
        )
        publish(snapshot)
    }

    static func publish(_ snapshot: WidgetGoalSnapshot) {
        guard let fileURL, let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    static func load() -> WidgetGoalSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(WidgetGoalSnapshot.self, from: data)
    }

    /// Clears the widget when the driver signs out, so a shared phone shows nothing stale.
    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
