import SwiftUI
import WidgetKit

/// Weekly goal progress on the home screen and in the lock-screen accessory slots.
struct WeeklyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.kind, provider: WeeklyGoalProvider()) { entry in
            WeeklyGoalWidgetView(snapshot: entry.snapshot)
                .containerBackground(Color.forestBackground, for: .widget)
        }
        .configurationDisplayName("widget.goal.title")
        .description("widget.goal.description")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct WeeklyGoalEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetGoalSnapshot?
}

/// Reads the snapshot the app publishes to the shared App Group.
///
/// Refreshes hourly: the underlying numbers only move when the driver saves a load, and the app
/// reloads the timeline directly at that moment.
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

struct WeeklyGoalWidgetView: View {

    let snapshot: WidgetGoalSnapshot?

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var circular: some View {
        Gauge(value: snapshot?.progressFraction ?? 0) {
            Image(systemName: "target")
        } currentValueLabel: {
            Text(Formatters.percent(snapshot?.progressFraction ?? 0))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            Text(Formatters.money(snapshot?.gross ?? 0))
                .font(.appNumber)
                .foregroundStyle(Color.forestText)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            ProgressView(value: snapshot?.progressFraction ?? 0)
                .tint(snapshot?.status.tint ?? .forestPrimary)
            Text(subtitle)
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
                .lineLimit(1)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            small
            VStack(alignment: .leading, spacing: 6) {
                if let snapshot, snapshot.target > 0 {
                    Text("goal.of \(Formatters.money(snapshot.target))")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    Label(snapshot.status.title, systemImage: snapshot.status.systemImage)
                        .font(.appCaptionMedium)
                        .foregroundStyle(snapshot.status.tint)
                    Text("goal.daysLeft")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    Text("\(snapshot.daysRemaining)")
                        .font(.appNumber)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        Text(snapshot?.weekLabel ?? String(localized: "widget.goal.title"))
            .font(.appCaption)
            .foregroundStyle(Color.forestTextSecondary)
            .lineLimit(1)
    }

    private var subtitle: String {
        guard let snapshot, snapshot.target > 0 else {
            return String(localized: "widget.goal.noGoal")
        }
        guard snapshot.dailyTargetNeeded > 0 else {
            return String(localized: "goal.status.met")
        }
        return String(localized: "goal.dailyNeeded") + " " + Formatters.money(snapshot.dailyTargetNeeded)
    }
}

#Preview(as: .systemSmall) {
    WeeklyGoalWidget()
} timeline: {
    WeeklyGoalEntry(date: .now, snapshot: .placeholder)
}
