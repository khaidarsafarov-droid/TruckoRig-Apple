import Foundation
import WidgetKit

/// Hands the widget its data through the shared App Group.
///
/// The widget does not open the encrypted journal and never sees the SQLCipher key. The app
/// publishes a tiny read-only snapshot after `WeeklyGoalCalculator` has already run inside the
/// process that holds the key. Nothing identifying goes in the file. `WidgetCenter` reloads the
/// timeline as soon as the file changes, so a saved load shows up without waiting for the
/// hourly fallback.
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
