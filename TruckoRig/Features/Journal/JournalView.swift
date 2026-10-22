import SwiftUI

/// Where the home menu pushes.
enum HomeDestination: Hashable {
    case analytics
    case goal
    case paycheck
    case diesel
    case maintenance
    case map
    case gallery
    case settings
    case profile
    case tax
    case expenses
    case about
    case privacy
}

/// Home screen: week card, then every trip, newest week first.
struct JournalView: View {

    @Environment(AppState.self) private var appState

    private var loads: [Load] { appState.catalog.loads }

    @State private var viewModel = JournalViewModel()
    @State private var isAddingLoad = false
    @State private var isSearching = false
    @State private var showMenu = false
    @State private var destination: HomeDestination?
    @State private var cameraLoad: Load?
    @State private var scannerLoad: Load?
    @State private var syncNotice: String?

    private var sections: [JournalSection] {
        viewModel.sections(from: loads, week: appState.settings.truckingWeek)
    }

    private var currentWeek: WeekRef {
        appState.settings.truckingWeek.currentWeek()
    }

    var body: some View {
        @Bindable var model = viewModel

        List {
            Section {
                JournalHomeHeader(
                    name: appState.catalog.profile?.name ?? "",
                    onMenu: { showMenu = true },
                    onSearch: { isSearching = true },
                    onProfile: { destination = .profile }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 12))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if !loads.isEmpty {
                    weekHero
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.loads) { load in
                        NavigationLink(value: load) {
                            JournalLoadCard(
                                load: load,
                                thresholds: appState.settings.rpmThresholds,
                                onCamera: { cameraLoad = load },
                                onScan: { scannerLoad = load }
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.loadPendingDeletion = load
                            } label: {
                                Label("action.delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    if section.week != currentWeek {
                        WeekHeaderView(section: section)
                    }
                }
            }

            if loads.isEmpty {
                emptyState
            } else if sections.isEmpty {
                noResultsState
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .forestBackground()
        .refreshable {
            syncNotice = await appState.telegram.pullToRefresh()
        }
        .overlay(alignment: .bottom) {
            if let syncNotice {
                Text(syncNotice)
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.heroText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.forestPrimary, in: Capsule())
                    .padding(.bottom, 12)
                    .task(id: syncNotice) {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        self.syncNotice = nil
                    }
            }
        }
        .navigationTitle("")
        .toolbar(isSearching ? .visible : .hidden, for: .navigationBar)
        .navigationDestination(for: Load.self) { load in
            LoadDetailView(load: load)
        }
        .navigationDestination(item: $destination) { dest in
            destinationView(dest)
        }
        .searchable(text: $model.searchText, isPresented: $isSearching, prompt: Text("journal.search.prompt"))
        .sheet(isPresented: $showMenu) {
            JournalMenuSheet(
                filter: $model.filter,
                onAdd: {
                    showMenu = false
                    isAddingLoad = true
                },
                onSelect: { dest in
                    showMenu = false
                    destination = dest
                }
            )
            .environment(appState)
        }
        .sheet(isPresented: $isAddingLoad) {
            AddLoadView()
                .presentationDetents([.large])
        }
        .sheet(item: $cameraLoad) { load in
            NavigationStack {
                CameraView(load: load)
            }
        }
        .sheet(item: $scannerLoad) { load in
            NavigationStack {
                ScannerView(load: load)
            }
        }
        .confirmationDialog(
            "journal.delete.confirm",
            isPresented: .isPresented($model.loadPendingDeletion),
            titleVisibility: .visible
        ) {
            Button("action.delete", role: .destructive) { deletePending() }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text(viewModel.loadPendingDeletion?.tripId ?? "")
        }
        .alert(
            "error.title",
            isPresented: .isPresented($model.errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(viewModel.errorMessage ?? "") }
        )
    }

    private var weekHero: some View {
        let week = appState.settings.truckingWeek
        let ref = currentWeek
        let weekLoads = loads.filter { $0.weekNumber == ref.weekNumber && $0.year == ref.year }
        let progress = WeeklyGoalCalculator(week: week, locale: .current).calculate(
            target: appState.settings.weeklyGoal,
            loads: weekLoads.map(\.summary),
            for: ref
        )
        let caption: String = {
            guard let start = week.startDate(of: ref), let end = week.endDate(of: ref) else { return progress.weekLabel }
            return SplitWeekRange.homeCaption(start: start, end: end, calendar: week.calendar, locale: .current)
        }()
        let rpm = progress.totalMiles > 0 ? USMoneyFormat.rpmPerMile(progress.currentGross / progress.totalMiles) : "—"
        return HomeWeekHeroCard(
            weekNumber: ref.weekNumber,
            rangeCaption: caption,
            gross: progress.currentGross,
            goal: progress.targetAmount,
            percent: progress.progressPercent,
            rpmText: rpm,
            milesText: USMoneyFormat.number(progress.totalMiles),
            loadCount: progress.loadsCount,
            dayLabels: narrowDays(week: week, ref: ref),
            elapsedDays: week.daysElapsed(),
            onOpenGoal: { destination = .goal }
        )
    }

    private func narrowDays(week: TruckingWeek, ref: WeekRef) -> [String] {
        guard let start = week.startDate(of: ref) else { return [] }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = week.calendar
        formatter.timeZone = week.calendar.timeZone
        formatter.dateFormat = "EEEEE"
        return (0..<7).compactMap { offset in
            guard let day = week.calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return formatter.string(from: day)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: HomeDestination) -> some View {
        switch destination {
        case .analytics: AnalyticsView()
        case .goal: WeeklyGoalView()
        case .paycheck: PaycheckListView()
        case .diesel: DieselListView()
        case .maintenance: MaintenanceListView()
        case .map: RouteMapView()
        case .gallery: GalleryView()
        case .settings: SettingsView()
        case .profile: ProfileView()
        case .tax: TaxTrackerView()
        case .expenses: MiscExpenseListView()
        case .about: AboutView()
        case .privacy: PrivacyView()
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "tray",
            title: "journal.empty.title",
            message: "journal.empty.message",
            actionTitle: "journal.addLoad",
            action: { isAddingLoad = true }
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var noResultsState: some View {
        EmptyStateView(
            systemImage: "magnifyingglass",
            title: "journal.noResults.title",
            message: "journal.noResults.message"
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func deletePending() {
        guard let load = viewModel.loadPendingDeletion else { return }
        viewModel.loadPendingDeletion = nil
        let repository = appState.loadRepository()
        do {
            try repository.delete(load, mediaStore: MediaStore(scope: appState.persistence.scope))
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

private struct JournalMenuSheet: View {
    @Binding var filter: JournalViewModel.Filter
    var onAdd: () -> Void
    var onSelect: (HomeDestination) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Picker("journal.filter", selection: $filter) {
                    ForEach(JournalViewModel.Filter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Button(action: onAdd) {
                    Label("journal.addLoad", systemImage: "plus")
                }

                menuRow(.analytics, "screen.analytics", "chart.bar")
                menuRow(.goal, "tab.goal", "target")
                menuRow(.paycheck, "screen.paycheck", "dollarsign.circle")
                menuRow(.diesel, "screen.diesel", "fuelpump")
                menuRow(.expenses, "screen.expenses", "receipt")
                menuRow(.tax, "screen.tax", "percent")
                menuRow(.maintenance, "screen.maintenance", "wrench.and.screwdriver")
                menuRow(.map, "screen.map", "map")
                menuRow(.gallery, "screen.gallery", "photo.on.rectangle")
                menuRow(.settings, "screen.settings", "gearshape")
                menuRow(.profile, "tab.profile", "person.crop.circle")
            }
            .navigationTitle("app.name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func menuRow(_ destination: HomeDestination, _ title: LocalizedStringKey, _ symbol: String) -> some View {
        Button { onSelect(destination) } label: {
            Label(title, systemImage: symbol)
        }
    }
}

#Preview {
    PreviewHost {
        NavigationStack {
            JournalView()
        }
    }
}
