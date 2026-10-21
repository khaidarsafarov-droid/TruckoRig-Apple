import SwiftUI
import WidgetKit

/// Records frames for the widget layout test. Production passes `nil`.
final class WidgetLayoutProbe {
    var frames: [String: CGRect] = [:]
}

/// Midnight & Gold split header.
///
/// Both sizes keep three labeled actions — Камера, Сканер, Дизель — in that order. Medium shows
/// the week, the total, the RPM pill, the goal line and an indigo bar. Small keeps the total,
/// the `% · goal` line and a thin gold bar inside the dark header, then three icon-over-label
/// tiles. There is no per-day chart: the approved mockup dropped it so nothing is clipped.
struct WeeklyGoalWidgetView: View {

    let snapshot: WidgetGoalSnapshot?
    var probe: WidgetLayoutProbe?
    /// Tests pass the size directly. WidgetKit's `widgetFamily` key path is read-only.
    var familyOverride: WidgetFamily? = nil

    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var data: WidgetGoalSnapshot { snapshot ?? .placeholder }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var circular: some View {
        Gauge(value: data.progressFraction) {
            Image(systemName: "target")
        } currentValueLabel: {
            Text(USMoneyFormat.ringPercent(data.progressPercent))
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var medium: some View {
        VStack(spacing: 0) {
            mediumHeader
            VStack(spacing: 4) {
                goalLine
                goalBar(fill: Color.widgetIndigo, height: 6)
                    .reportFrame("wg.bar", probe)
                actionRow(style: .labeled)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.forestCard)
        }
    }

    private var mediumHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Link(destination: WidgetDeepLink.url(for: .home)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(data.weekRange)
                        .font(widgetFont(.medium, 12))
                        .foregroundStyle(Color.heroText)
                        .lineLimit(1)
                        .reportFrame("wg.week", probe)
                    Text(USMoneyFormat.currency(data.gross))
                        .font(widgetFont(.bold, 24))
                        .foregroundStyle(Color.heroText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .reportFrame("wg.gross", probe)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if data.rpm > 0 {
                Link(destination: WidgetDeepLink.url(for: .analytics)) {
                    Text(String(localized: "widget.rpm.pill \(USMoneyFormat.rpm(data.rpm))"))
                        .font(widgetFont(.bold, 11))
                        .foregroundStyle(Color.forestSuccess)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.successContainer, in: Capsule())
                        .reportFrame("wg.rpm", probe)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroGradient())
    }

    private var small: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Link(destination: WidgetDeepLink.url(for: .home)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(USMoneyFormat.currency(data.gross))
                            .font(widgetFont(.bold, 22))
                            .foregroundStyle(Color.heroText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .reportFrame("wg.gross", probe)
                        Text(smallMetric)
                            .font(widgetFont(.medium, 11))
                            .foregroundStyle(Color.heroText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .reportFrame("wg.percent", probe)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                goalBar(fill: Color.brandGold, track: Color.heroText.opacity(0.22), height: 4)
                    .reportFrame("wg.bar", probe)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HeroGradient())

            actionRow(style: .stacked)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.forestCard)
        }
    }

    private var goalLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(percentLine)
                .font(widgetFont(.medium, 12))
                .foregroundStyle(Color.forestText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .reportFrame("wg.percent", probe)
            Spacer(minLength: 4)
            if data.hasGoal {
                Text(String(localized: "widget.goal.remaining \(USMoneyFormat.currency(data.remaining))"))
                    .font(widgetFont(.medium, 12))
                    .foregroundStyle(Color.forestTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .reportFrame("wg.remaining", probe)
            }
        }
    }

    private var percentLine: String {
        guard data.hasGoal else { return String(localized: "widget.goal.noGoal") }
        return String(localized: "widget.goal.percent \(USMoneyFormat.ringPercent(data.progressPercent))")
    }

    private var smallMetric: String {
        guard data.hasGoal else { return String(localized: "widget.goal.noGoal") }
        return String(
            localized: "widget.goal.micro \(USMoneyFormat.ringPercent(data.progressPercent)) \(USMoneyFormat.currency(data.target))"
        )
    }

    private func goalBar(fill: Color, track: Color = Color.forestSurfaceMuted, height: CGFloat) -> some View {
        Capsule()
            .fill(track)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(fill)
                        .frame(width: max(height, geo.size.width * data.progressFraction))
                }
            }
            .clipShape(Capsule())
            .accessibilityLabel(percentLine)
    }

    private func actionRow(style: WidgetActionStyle) -> some View {
        HStack(spacing: 6) {
            action(.camera, "camera", style: style)
            action(.scanner, "doc.viewfinder", style: style)
            action(.diesel, "fuelpump", style: style)
        }
    }

    private func action(_ kind: WidgetActionKind, _ symbol: String, style: WidgetActionStyle) -> some View {
        Link(destination: kind.url) {
            Group {
                switch style {
                case .labeled:
                    HStack(spacing: 4) {
                        Image(systemName: symbol)
                            .font(widgetFont(.medium, 14))
                        Text(kind.title)
                            .font(widgetFont(.medium, 12))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                case .stacked:
                    VStack(spacing: 4) {
                        Image(systemName: symbol)
                            .font(widgetFont(.medium, 16))
                        Text(kind.title)
                            .font(widgetFont(.medium, 11))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .foregroundStyle(Color.widgetIndigo)
            .background(Color.forestSurfaceMuted, in: RoundedRectangle(cornerRadius: style == .labeled ? 18 : 16, style: .continuous))
            .reportFrame(kind.frameID, probe)
        }
        .accessibilityIdentifier(kind.frameID)
        .accessibilityLabel(kind.title)
    }
}

private enum WidgetActionStyle {
    case labeled
    case stacked
}

enum WidgetActionKind: String, CaseIterable {
    case camera
    case scanner
    case diesel

    var route: WidgetRoute {
        switch self {
        case .camera: return .camera
        case .scanner: return .scanner
        case .diesel: return .addDiesel
        }
    }

    var url: URL { WidgetDeepLink.url(for: route) }

    var title: String {
        switch self {
        case .camera: return String(localized: "widget.action.camera")
        case .scanner: return String(localized: "widget.action.scanner")
        case .diesel: return String(localized: "widget.action.diesel")
        }
    }

    var frameID: String {
        switch self {
        case .camera: return "wg.action.camera"
        case .scanner: return "wg.action.scanner"
        case .diesel: return "wg.action.diesel"
        }
    }
}

extension Color {
    /// Indigo that stays indigo on the widget's light plate. Dark-mode `forestPrimary` is gold.
    static let widgetIndigo = Color(hex: "3F3D9E")
}

private func widgetFont(_ weight: AppFont.Weight, _ size: CGFloat) -> Font {
    Font(AppFont.uiFont(weight, size: size))
}

private extension View {
    func reportFrame(_ id: String, _ probe: WidgetLayoutProbe?) -> some View {
        background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { probe?.frames[id] = geo.frame(in: .global) }
                    .onChange(of: geo.size) { _, _ in
                        probe?.frames[id] = geo.frame(in: .global)
                    }
            }
        }
    }
}
