import SwiftUI

/// Home screen: week card, then every trip, newest week first.
struct JournalView: View {

    @Environment(AppState.self) private var appState

    private var loads: [Load] { appState.catalog.loads }

    @State private var viewModel = JournalViewModel()
    @State private var isAddingLoad = false
    @State private var isSearching = false
    @State private var cameraLoad: Load?
    @State private var scannerLoad: Load?
    @State private var syncNotice: String?
    @State private var showSurveyPaywall = false
    @State private var showSurvey = false
    /// iPad split view. The phone list uses `NavigationLink` instead.
    @State private var selectedLoadID: UUID?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var sections: [JournalSection] {
        viewModel.sections(from: loads, week: appState.settings.truckingWeek, locale: AppLocale.locale)
    }

    private var currentWeek: WeekRef {
        appState.settings.truckingWeek.currentWeek()
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            NavigationSplitView {
                journalList
            } detail: {
                if let selectedLoadID, let load = loads.first(where: { $0.id == selectedLoadID }) {
                    LoadDetailView(load: load)
                } else {
                    ContentUnavailableView {
                        Label("journal.select.title", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("journal.select.message")
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            journalList
        }
    }

    private var journalList: some View {
        @Bindable var model = viewModel

        return List {
            Section {
                JournalHomeHeader(
                    name: appState.catalog.profile?.name ?? "",
                    onAdd: { isAddingLoad = true },
                    onSearch: { isSearching = true }
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

            if loads.isEmpty {
                ActivationChecklistCard(
                    profileComplete: !(appState.catalog.profile?.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty,
                    hasGoal: appState.settings.weeklyGoal > 0,
                    hasDiesel: !appState.catalog.diesel.isEmpty
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if showSurvey {
                Day7SurveyBanner(
                    onSubscribe: { showSurveyPaywall = true },
                    onEnough: {
                        var record = Day7SurveyStore(scope: appState.persistence.scope).load(now: Date())
                        record = Day7SurveyPolicy.optOut(record)
                        Day7SurveyStore(scope: appState.persistence.scope).save(record)
                        showSurvey = false
                    }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            journalFilter
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ForEach(sections) { section in
                Section {
                    ForEach(section.loads) { load in
                        loadLink(load)
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
        .searchable(text: $model.searchText, isPresented: $isSearching, prompt: Text("journal.search.prompt"))
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
        .sheet(isPresented: $showSurveyPaywall) {
            PremiumPaywallSheet(onClose: { showSurveyPaywall = false })
                .environment(appState)
        }
        .task {
            let store = Day7SurveyStore(scope: appState.persistence.scope)
            var record = store.load(now: Date())
            let due = Day7SurveyPolicy.shouldShow(record, now: Date(), premiumActive: appState.premium.isActive)
            if due {
                record = Day7SurveyPolicy.recordDisplay(record, now: Date())
                store.save(record)
            }
            showSurvey = due
        }
    }

    private var weekHero: some View {
        let week = appState.settings.truckingWeek
        let ref = currentWeek
        let weekLoads = loads.filter { $0.weekNumber == ref.weekNumber && $0.year == ref.year }
        let locale = AppLocale.locale
        let progress = WeeklyGoalCalculator(week: week, locale: locale).calculate(
            target: appState.settings.weeklyGoal,
            loads: weekLoads.map(\.summary),
            for: ref
        )
        let caption: String = {
            guard let start = week.startDate(of: ref), let end = week.endDate(of: ref) else { return progress.weekLabel }
            return SplitWeekRange.homeCaption(start: start, end: end, calendar: week.calendar, locale: locale)
        }()
        let system = appState.settings.measurementSystem
        let rpm = progress.totalMiles > 0
            ? USMoneyFormat.rpmPerMile(progress.currentGross / progress.totalMiles, system: system)
            : "—"
        return HomeWeekHeroCard(
            weekNumber: ref.weekNumber,
            rangeCaption: caption,
            gross: progress.currentGross,
            goal: progress.targetAmount,
            percent: progress.progressPercent,
            rpmText: rpm,
            milesText: USMoneyFormat.number(MeasurementUnits.displayDistance(progress.totalMiles, system: system)),
            measurementSystem: system,
            loadCount: progress.loadsCount,
            dayLabels: narrowDays(week: week, ref: ref),
            elapsedDays: week.daysElapsed()
        )
    }

    private func narrowDays(week: TruckingWeek, ref: WeekRef) -> [String] {
        guard let start = week.startDate(of: ref) else { return [] }
        let formatter = DateFormatter()
        formatter.locale = AppLocale.locale
        formatter.calendar = week.calendar
        formatter.timeZone = week.calendar.timeZone
        formatter.dateFormat = "EEEEE"
        return (0..<7).compactMap { offset in
            guard let day = week.calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return formatter.string(from: day)
        }
    }

    private var journalFilter: some View {
        @Bindable var model = viewModel
        return VStack(alignment: .leading, spacing: 8) {
            Picker("journal.filter", selection: $model.filter) {
                ForEach(JournalViewModel.Filter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)
            .font(.appCaptionMedium)
            if model.filter == .onDate || model.filter == .calendarWeek {
                DatePicker("journal.filter.pickDate", selection: $model.selectedDay, displayedComponents: .date)
            }
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

    private func loadLink(_ load: Load) -> some View {
        let card = JournalLoadCard(
            load: load,
            thresholds: appState.settings.rpmThresholds,
            onCamera: { cameraLoad = load },
            onScan: { scannerLoad = load }
        )
        return Group {
            if horizontalSizeClass == .regular {
                Button { selectedLoadID = load.id } label: { card }
            } else {
                NavigationLink(value: load) { card }
            }
        }
        .buttonStyle(.plain)
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

#if DEBUG
#Preview {
    PreviewHost {
        NavigationStack {
            JournalView()
        }
    }
}
#endif
