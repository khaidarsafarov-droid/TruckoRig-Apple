import SwiftUI

/// Business screens that belong with the journal. On iPhone they open from the journal menu.
/// On iPad the sidebar already lists them, so the menu stays hidden.
enum JournalTool: String, CaseIterable, Identifiable, Hashable {
    case analytics
    case paycheck
    case diesel
    case expenses
    case tax
    case maintenance
    case gallery
    case map

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .analytics: return "screen.analytics"
        case .paycheck: return "screen.paycheck"
        case .diesel: return "screen.diesel"
        case .expenses: return "screen.expenses"
        case .tax: return "screen.tax"
        case .maintenance: return "screen.maintenance"
        case .gallery: return "screen.gallery"
        case .map: return "screen.map"
        }
    }

    var systemImage: String {
        switch self {
        case .analytics: return "chart.bar"
        case .paycheck: return "dollarsign.circle"
        case .diesel: return "fuelpump"
        case .expenses: return "receipt"
        case .tax: return "percent"
        case .maintenance: return "wrench.and.screwdriver"
        case .gallery: return "photo.on.rectangle"
        case .map: return "map"
        }
    }
}

struct JournalToolsMenu: View {
    var onTool: (JournalTool) -> Void

    var body: some View {
        Menu {
            ForEach(JournalTool.allCases) { tool in
                Button {
                    onTool(tool)
                } label: {
                    Label(tool.title, systemImage: tool.systemImage)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.forestText)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("profile.records")
    }
}

struct JournalToolScreen: View {
    let tool: JournalTool

    var body: some View {
        screen
            .toolbar(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private var screen: some View {
        switch tool {
        case .analytics: AnalyticsView()
        case .paycheck: PaycheckListView()
        case .diesel: DieselListView()
        case .expenses: MiscExpenseListView()
        case .tax: TaxTrackerView()
        case .maintenance: MaintenanceListView()
        case .gallery: GalleryView()
        case .map: MapScreen()
        }
    }
}
