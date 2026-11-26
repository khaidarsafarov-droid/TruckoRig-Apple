import SwiftUI
import WidgetKit

/// Records frames for the widget layout test. Production passes `nil`.
final class WidgetLayoutProbe {
    var frames: [String: CGRect] = [:]
}

/// Midnight & Gold split header.
///
/// Both sizes keep three labeled actions — Камера, Сканер, Дизель — in that order. Medium shows
/// the week, the total, the RPM pill beside that total, the goal line and an indigo bar. Small
/// keeps the total, the `% · goal` line and a thin gold bar inside the dark header, then three
/// icon-over-label tiles. There is no per-day chart: the approved mockup dropped it so nothing
/// is clipped.
struct WeeklyGoalWidgetView: View {

    let snapshot: WidgetGoalSnapshot?
    var probe: WidgetLayoutProbe?
    /// Tests pass the size directly. WidgetKit's `widgetFamily` key path is read-only.
    var familyOverride: WidgetFamily? = nil

    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var data: WidgetGoalSnapshot { snapshot ?? .placeholder }

    /// The app publishes the resolved system into the App Group. Miles when it has not yet.
    private var measurementSystem: MeasurementSystem {
        UnitPreference.readResolved(UserDefaults(suiteName: WidgetBridge.appGroup))
    }

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
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var medium: some View {
        VStack(spacing: 0) {
            mediumHeader
            VStack(spacing: 4) {
                goalLine
                goalBar(fill: Color.forestPrimary, height: 6)
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
        VStack(alignment: .leading, spacing: 1) {
            Link(destination: WidgetDeepLink.url(for: .home)) {
                Text(data.weekRange)
                    .font(widgetFont(.medium, 12))
                    .foregroundStyle(Color.heroText)
                    .lineLimit(1)
                    .reportFrame("wg.week", probe)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .center, spacing: 8) {
                Link(destination: WidgetDeepLink.url(for: .home)) {
                    Text(USMoneyFormat.currency(data.gross))
                        .font(widgetFont(.bold, 24))
                        .foregroundStyle(Color.heroText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .reportFrame("wg.gross", probe)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if data.rpm > 0 {
                    rpmPill
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroGradient())
    }

    /// Dark-hero capsule. The header gradient stays midnight in light, dark, and OLED
    /// (the widget does not apply `oledDarkActive`), so the pill does not switch palettes.
    private var rpmPill: some View {
        Link(destination: WidgetDeepLink.url(for: .analytics)) {
            Text(rpmLabel)
                .font(widgetFont(.semibold, RpmPillChrome.fontSize))
                .foregroundStyle(RpmPillChrome.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RpmPillChrome.fill, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(RpmPillChrome.stroke, lineWidth: 1)
                }
                .reportFrame("wg.rpm", probe)
        }
        .layoutPriority(1)
    }

    private var rpmLabel: String {
        let shown = MeasurementUnits.displayPerDistance(data.rpm, system: measurementSystem)
        return String(localized: "widget.rpm.pill \(USMoneyFormat.rpm(shown))")
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
                            .minimumScaleFactor(0.45)
                            .reportFrame("wg.percent", probe)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                goalBar(fill: Color.brandGold, track: AnyShapeStyle(Color.heroText.opacity(0.22)), height: 4)
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
                .minimumScaleFactor(0.45)
                .layoutPriority(1)
                .reportFrame("wg.percent", probe)
            Spacer(minLength: 4)
            if data.hasGoal {
                Text(String(localized: "widget.goal.remaining \(USMoneyFormat.currency(data.remaining))"))
                    .font(widgetFont(.medium, 12))
                    .foregroundStyle(Color.forestTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
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

    private func goalBar(
        fill: Color,
        track: AnyShapeStyle = AnyShapeStyle(Color.forestSurfaceMuted),
        height: CGFloat
    ) -> some View {
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
            .foregroundStyle(Color.forestPrimary)
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

/// Hero RPM capsule. The goal line and the week caption are both 12pt medium;
/// 13pt semibold sits with that goal line and reads larger than the caption.
private enum RpmPillChrome {
    static let fontSize: CGFloat = 13
    static let text = Color(hex: "6EE7A0")
    static let fill = Color(hex: "124030")
    /// Same green as the label, thinned to a 1pt hairline.
    static let stroke = Color(hex: "6EE7A0").opacity(0.45)
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
    /// Indigo that stays indigo. Dark-mode `forestPrimary` is gold, which charts should not pick up.
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
