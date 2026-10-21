import SwiftUI
import WidgetKit

/// Weekly goal on the home screen, with camera, scanner and diesel deep links.
struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.kind, provider: WeeklyGoalProvider()) { entry in
            WeeklyGoalWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.forestCard }
        }
        .configurationDisplayName(Text("app.name"))
        .description(Text("widget.goal.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

struct WeeklyGoalEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetGoalSnapshot?
}

/// Reads the snapshot the app publishes to the shared App Group.
///
/// Refreshes hourly as a fallback. The app reloads this timeline itself whenever a load or the
/// weekly goal changes, so the numbers do not wait for the hour.
struct WeeklyGoalProvider: TimelineProvider {

    func placeholder(in context: Context) -> WeeklyGoalEntry {
        WeeklyGoalEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyGoalEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : WidgetBridge.load()
        completion(WeeklyGoalEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyGoalEntry>) -> Void) {
        let entry = WeeklyGoalEntry(date: Date(), snapshot: WidgetBridge.load())
        let nextRefresh = Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

#Preview(as: .systemSmall) {
    WeeklyGoalWidget()
} timeline: {
    WeeklyGoalEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemMedium) {
    WeeklyGoalWidget()
} timeline: {
    WeeklyGoalEntry(date: .now, snapshot: .placeholder)
}
