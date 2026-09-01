import SwiftUI

/// Chooses between the login wall, the phone tab bar and the iPad sidebar.
struct RootView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                SidebarView()
            } else {
                MainTabView()
            }
        }
        .fullScreenCover(isPresented: .constant(appState.needsAuthentication)) {
            WelcomeView()
        }
        .onChange(of: appState.auth.session) {
            appState.applySessionScope()
        }
    }
}

/// Phone layout: three tabs, everything else pushed or presented from them.
struct MainTabView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.selectedTab) {
            ForEach(MainTab.allCases) { tab in
                NavigationStack {
                    destination(for: tab)
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func destination(for tab: MainTab) -> some View {
        switch tab {
        case .journal: JournalView()
        case .goal: WeeklyGoalView()
        case .profile: ProfileView()
        }
    }
}

/// iPad and landscape layout: the same destinations, plus the secondary screens that are
/// navigation pushes on a phone.
struct SidebarView: View {

    @Environment(AppState.self) private var appState
    @State private var selection: SidebarItem? = .journal

    enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
        case journal, goal, analytics, paycheck, diesel, maintenance, map, gallery, profile, settings

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .journal: return "tab.journal"
            case .goal: return "tab.goal"
            case .analytics: return "screen.analytics"
            case .paycheck: return "screen.paycheck"
            case .diesel: return "screen.diesel"
            case .maintenance: return "screen.maintenance"
            case .map: return "screen.map"
            case .gallery: return "screen.gallery"
            case .profile: return "tab.profile"
            case .settings: return "screen.settings"
            }
        }

        var systemImage: String {
            switch self {
            case .journal: return "list.bullet.rectangle"
            case .goal: return "target"
            case .analytics: return "chart.bar"
            case .paycheck: return "dollarsign.circle"
            case .diesel: return "fuelpump"
            case .maintenance: return "wrench.and.screwdriver"
            case .map: return "map"
            case .gallery: return "photo.on.rectangle"
            case .profile: return "person.crop.circle"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .navigationTitle("app.name")
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                destination(for: selection ?? .journal)
            }
        }
    }

    @ViewBuilder
    private func destination(for item: SidebarItem) -> some View {
        switch item {
        case .journal: JournalView()
        case .goal: WeeklyGoalView()
        case .analytics: AnalyticsView()
        case .paycheck: PaycheckListView()
        case .diesel: DieselListView()
        case .maintenance: MaintenanceListView()
        case .map: RouteMapView()
        case .gallery: GalleryView()
        case .profile: ProfileView()
        case .settings: SettingsView()
        }
    }
}
