import SwiftUI

/// Chooses between the phone tab bar and the iPad sidebar.
struct RootView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !appState.settings.onboardingComplete {
                OnboardingView()
            } else if horizontalSizeClass == .regular {
                SidebarView()
            } else {
                MainTabView()
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { appState.premium.shouldShowFirstRun },
                set: { presented in
                    if !presented { appState.premium.declineFirstRun() }
                }
            )
        ) {
            PremiumFirstRunOffer()
                .environment(appState)
        }
        .onOpenURL { url in
            appState.open(url)
        }
        .onChange(of: appState.settings.language) { _, _ in
            appState.publishWidgetSnapshot()
        }
        .onChange(of: appState.settings.weekStart) { _, _ in
            appState.publishWidgetSnapshot()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.telegram.resume()
                TelegramBackgroundRegistrar.submit()
                ICloudBackgroundRegistrar.submit()
                appState.icloud.start()
            } else if phase == .background {
                appState.telegram.pause()
                TelegramBackgroundRegistrar.submit()
                ICloudBackgroundRegistrar.submit()
                appState.icloud.syncOnBackground()
            }
        }
        .fullScreenCover(item: presentation) { route in
            WidgetPresentationCover(route: route)
                .environment(appState)
        }
    }

    private var presentation: Binding<WidgetPresentation?> {
        Binding(
            get: { appState.pendingPresentation },
            set: { appState.pendingPresentation = $0 }
        )
    }
}

/// What a `truckorig://` link presents on top of the tabs.
enum WidgetPresentation: String, Identifiable {
    case camera
    case scanner
    case addDiesel
    case addLoad
    case analytics

    var id: String { rawValue }
}

private struct WidgetPresentationCover: View {
    let route: WidgetPresentation

    var body: some View {
        switch route {
        case .camera:
            NavigationStack {
                AttachLoadPickView(mode: .camera)
            }
        case .scanner:
            NavigationStack {
                AttachLoadPickView(mode: .scanner)
            }
        case .addDiesel:
            DieselEditorView(fill: nil)
        case .addLoad:
            AddLoadView()
        case .analytics:
            AnalyticsView()
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
        case journal, goal, analytics, paycheck, diesel, expenses, tax, maintenance, map, gallery, profile, settings, privacy, about

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .journal: return "tab.journal"
            case .goal: return "tab.goal"
            case .analytics: return "screen.analytics"
            case .paycheck: return "screen.paycheck"
            case .diesel: return "screen.diesel"
            case .expenses: return "screen.expenses"
            case .tax: return "screen.tax"
            case .maintenance: return "screen.maintenance"
            case .map: return "screen.map"
            case .gallery: return "screen.gallery"
            case .profile: return "tab.profile"
            case .settings: return "screen.settings"
            case .privacy: return "screen.privacy"
            case .about: return "screen.about"
            }
        }

        var systemImage: String {
            switch self {
            case .journal: return "list.bullet.rectangle"
            case .goal: return "target"
            case .analytics: return "chart.bar"
            case .paycheck: return "dollarsign.circle"
            case .diesel: return "fuelpump"
            case .expenses: return "receipt"
            case .tax: return "percent"
            case .maintenance: return "wrench.and.screwdriver"
            case .map: return "map"
            case .gallery: return "photo.on.rectangle"
            case .profile: return "person.crop.circle"
            case .settings: return "gearshape"
            case .privacy: return "lock"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
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
        case .analytics: AnalyticsView(showsBackButton: false)
        case .paycheck: PaycheckListView()
        case .diesel: DieselListView()
        case .expenses: MiscExpenseListView()
        case .tax: TaxTrackerView()
        case .maintenance: MaintenanceListView()
        case .map: MapScreen()
        case .gallery: GalleryView()
        case .profile: ProfileView()
        case .settings: SettingsView()
        case .privacy: PrivacyView()
        case .about: AboutView()
        }
    }
}
