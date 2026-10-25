import SwiftUI

/// Identifiers of the included rows and free chips, in layout order.
struct PaywallRowIDKey: PreferenceKey {
    static var defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

/// Paid tools on the paywall, one row each, in the order the product lists them.
///
/// The last row is a file the driver can restore on Android or iPhone. iOS does not offer
/// Google Drive backup.
enum PaywallFeature: String, CaseIterable, Identifiable {
    case telegram
    case analytics
    case goal
    case map
    case tax
    case scanner
    case camera
    case export
    case fileBackup

    var id: String { rawValue }

    var accessibilityID: String { "paywall.feature.\(rawValue)" }

    var symbol: String {
        switch self {
        case .telegram: return "paperplane.fill"
        case .analytics: return "chart.line.uptrend.xyaxis"
        case .goal: return "flag.fill"
        // Joined so the symbol is not read as a localization key (`map.` is a string namespace).
        case .map: return ["map", "fill"].joined(separator: ".")
        case .tax: return "receipt"
        case .scanner: return "doc.viewfinder"
        // Joined so the symbol is not read as a localization key (`camera.` is a string namespace).
        case .camera: return ["camera", "fill"].joined(separator: ".")
        case .export: return "square.and.arrow.down"
        case .fileBackup: return "doc.on.doc.fill"
        }
    }

    var titleKeyName: String {
        switch self {
        case .telegram: return "premium.feature.telegram.title"
        case .analytics: return "premium.feature.analytics.title"
        case .goal: return "premium.feature.goal.title"
        case .map: return "premium.feature.map.title"
        case .tax: return "premium.feature.tax.title"
        case .scanner: return "premium.feature.scanner.title"
        case .camera: return "premium.feature.camera.title"
        case .export: return "premium.feature.export.title"
        case .fileBackup: return "premium.feature.backup.title"
        }
    }

    var benefitKeyName: String {
        switch self {
        case .telegram: return "premium.feature.telegram.benefit"
        case .analytics: return "premium.feature.analytics.benefit"
        case .goal: return "premium.feature.goal.benefit"
        case .map: return "premium.feature.map.benefit"
        case .tax: return "premium.feature.tax.benefit"
        case .scanner: return "premium.feature.scanner.benefit"
        case .camera: return "premium.feature.camera.benefit"
        case .export: return "premium.feature.export.benefit"
        case .fileBackup: return "premium.feature.backup.benefit"
        }
    }

    var titleKey: LocalizedStringKey { LocalizedStringKey(titleKeyName) }
    var benefitKey: LocalizedStringKey { LocalizedStringKey(benefitKeyName) }
}

/// Journal tools that stay free. Shown as chips under the paid rows.
enum PaywallFreeTool: String, CaseIterable, Identifiable {
    case loads
    case diesel
    case pay
    case deadhead

    var id: String { rawValue }

    var accessibilityID: String { "paywall.free.\(rawValue)" }

    var titleKeyName: String {
        switch self {
        case .loads: return "premium.free.loads"
        case .diesel: return "premium.free.diesel"
        case .pay: return "premium.free.pay"
        case .deadhead: return "premium.free.deadhead"
        }
    }

    var titleKey: LocalizedStringKey { LocalizedStringKey(titleKeyName) }
}

/// "What's included" list and the free-forever chips. Sits under the trial-and-price sentence.
struct PaywallIncludedSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("premium.included.title")
                .font(AppFont.font(.bold, size: 18, relativeTo: .title3))
                .foregroundStyle(Color.forestText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("paywall.included")
                .preference(key: PaywallRowIDKey.self, value: ["paywall.included"])
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(PaywallFeature.allCases.enumerated()), id: \.element.id) { index, feature in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.forestSeparator)
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    PaywallFeatureRow(feature: feature)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("premium.free.title")
                    .font(AppFont.font(.semibold, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.forestTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.free.title")
                    .preference(key: PaywallRowIDKey.self, value: ["paywall.free.title"])
                PaywallChipFlow(spacing: 8) {
                    ForEach(PaywallFreeTool.allCases) { tool in
                        PaywallFreeChip(tool: tool)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PaywallFeatureRow: View {
    var feature: PaywallFeature

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PaywallFeatureIcon(symbol: feature.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.titleKey)
                    .font(AppFont.font(.bold, size: 16, relativeTo: .headline))
                    .foregroundStyle(Color.forestText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(feature.benefitKey)
                    .font(.appCallout)
                    .foregroundStyle(Color.forestTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(feature.titleKey) + Text(verbatim: ". ") + Text(feature.benefitKey))
        .accessibilityIdentifier(feature.accessibilityID)
        .preference(key: PaywallRowIDKey.self, value: [feature.accessibilityID])
    }
}

private struct PaywallFreeChip: View {
    var tool: PaywallFreeTool

    var body: some View {
        Text(tool.titleKey)
            .font(AppFont.font(.semibold, size: 14, relativeTo: .subheadline))
            .foregroundStyle(Color.forestSecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.forestSurfaceMuted, in: Capsule())
            .accessibilityIdentifier(tool.accessibilityID)
            .preference(key: PaywallRowIDKey.self, value: [tool.accessibilityID])
    }
}

/// Gold mark. The circle is `#C8A867` at 18% on the light card. Dark and OLED use a
/// slightly stronger champagne wash so the same icon still reads on black.
private struct PaywallFeatureIcon: View {
    var symbol: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.brandGold.opacity(colorScheme == .dark ? 0.28 : 0.18))
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PaywallGold.icon)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

/// Icon on the gold wash. Darker gold on the light card, champagne on dark and OLED.
private enum PaywallGold {
    static let icon = Color.adaptive(light: "86542A", dark: "D6BC85")
}

/// Chips wrap onto the next line on a narrow phone and at accessibility text sizes.
private struct PaywallChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? idealWidth(subviews)
        let rows = pack(subviews, width: width)
        return CGSize(width: proposal.width ?? width, height: rowsHeight(rows))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = pack(subviews, width: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map(\.height).max() ?? 0
            for item in row {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.width, height: item.height)
                )
                x += item.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private struct Item {
        var subview: LayoutSubview
        var width: CGFloat
        var height: CGFloat
    }

    private func idealWidth(_ subviews: Subviews) -> CGFloat {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        return widths.reduce(0, +) + gaps
    }

    private func pack(_ subviews: Subviews, width: CGFloat) -> [[Item]] {
        let limit = width.isFinite ? max(width, 1) : .greatestFiniteMagnitude
        var rows: [[Item]] = []
        var row: [Item] = []
        var used: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > limit {
                size = subview.sizeThatFits(ProposedViewSize(width: limit, height: nil))
                size.width = min(max(size.width, 1), limit)
            }
            let gap: CGFloat = row.isEmpty ? 0 : spacing
            if !row.isEmpty, used + gap + size.width > limit + 0.5 {
                rows.append(row)
                row = []
                used = 0
            }
            let placedGap: CGFloat = row.isEmpty ? 0 : spacing
            row.append(Item(subview: subview, width: size.width, height: size.height))
            used += placedGap + size.width
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    private func rowsHeight(_ rows: [[Item]]) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        let content = rows.reduce(CGFloat(0)) { partial, row in
            partial + (row.map(\.height).max() ?? 0)
        }
        return content + spacing * CGFloat(rows.count - 1)
    }
}
