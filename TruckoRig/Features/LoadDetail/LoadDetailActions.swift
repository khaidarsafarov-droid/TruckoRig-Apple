import SwiftUI

/// Small status chips on the load card. Each one opens only that part of the editor.
struct LoadDetailActionChips: View {
    let load: Load
    var onMiles: () -> Void
    var onDeadhead: () -> Void
    var onFinish: () -> Void
    var onDispute: () -> Void

    @Environment(AppState.self) private var appState

    private var system: MeasurementSystem { appState.settings.measurementSystem }

    var body: some View {
        ChipFlow(spacing: 8) {
            chip(
                milesTitle,
                identifier: "uitest.chip.miles",
                tint: Color.forestPrimary,
                action: onMiles
            )
            chip(
                deadheadTitle,
                identifier: "uitest.chip.deadhead",
                tint: load.deadheadMiles > 0 ? Color.forestPrimary : Color.forestSecondary,
                action: onDeadhead
            )
            chip(
                finishTitle,
                identifier: "uitest.chip.finish",
                tint: load.actualFinishDate == nil ? Color.forestSecondary : Color.forestSuccess,
                action: onFinish
            )
            chip(
                disputeTitle,
                identifier: "uitest.chip.dispute",
                tint: disputeTint,
                action: onDispute
            )
        }
    }

    private var milesTitle: String {
        guard load.totalMiles > 0 else { return String(localized: "load.chip.miles.add") }
        let shown = Formatters.miles(load.totalMiles, system: system)
        return String(localized: "load.chip.miles.set \(shown)")
    }

    private var deadheadTitle: String {
        guard load.deadheadMiles > 0 else { return String(localized: "load.chip.deadhead.add") }
        let shown = Formatters.miles(load.deadheadMiles, system: system)
        return String(localized: "load.chip.deadhead.set \(shown)")
    }

    private var finishTitle: String {
        load.actualFinishDate == nil
            ? String(localized: "load.chip.finish.add")
            : String(localized: "load.chip.finish.done")
    }

    private var disputeTitle: String {
        if !load.isDispute { return String(localized: "load.chip.dispute.add") }
        if load.disputeCompleted { return String(localized: "load.dispute.completed") }
        return String(localized: "load.dispute.open")
    }

    private var disputeTint: Color {
        if load.disputeCompleted { return Color.forestSuccess }
        if load.isDispute { return Color.forestWarning }
        return Color.forestSecondary
    }

    private func chip(_ title: String, identifier: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appCaptionMedium)
                .foregroundStyle(tint)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// Wraps chips onto the next line instead of stretching them into full-width buttons.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let rows = wrap(subviews, maxWidth: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width == .greatestFiniteMagnitude ? (rows.map(\.width).max() ?? 0) : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = wrap(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.view.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        var view: LayoutSubview
        var size: CGSize
    }

    private struct Row {
        var items: [Item]
        var width: CGFloat
        var height: CGFloat
    }

    private func wrap(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var items: [Item] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let next = items.isEmpty ? size.width : rowWidth + spacing + size.width
            if !items.isEmpty, next > maxWidth {
                rows.append(Row(items: items, width: rowWidth, height: rowHeight))
                items = []
                rowWidth = 0
                rowHeight = 0
            }
            items.append(Item(view: view, size: size))
            rowWidth = items.count == 1 ? size.width : rowWidth + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }
        if !items.isEmpty {
            rows.append(Row(items: items, width: rowWidth, height: rowHeight))
        }
        return rows
    }
}
