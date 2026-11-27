import SwiftUI

/// Home screen: week card, then every trip, newest week first.
struct JournalView: View {

    @Environment(AppState.self) private var appState

    private var loads: [Load] { appState.catalog.loads }

    @State private var viewModel = JournalViewModel()
    @State private var isAddingLoad = false
    @State private var isSearching = false
    @State private var tool: JournalTool?
    @State private var cameraLoad: Load?
    @State private var scannerLoad: Load?
    @State private var syncNotice: String?
    @State private var showSurveyPaywall = false
    @State private var showSurvey = false
    @State private var isChoosingShareFormat = false
    @State private var shareActivity: PeriodReportActivity?
    /// iPad split view. The phone list uses `NavigationLink` instead.
    @State private var selectedLoadID: UUID?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.suppressesJournalSplit) private var suppressesJournalSplit

    private var showsSplit: Bool { horizontalSizeClass == .regular && !suppressesJournalSplit }
    /// iPad sidebar: list and load side by side in the sidebar's detail column (no nested split).
    private var showsInlineSplit: Bool { horizontalSizeClass == .regular && suppressesJournalSplit }

    private var selectedLoad: Load? {
        guard let selectedLoadID else { return nil }
        return loads.first(where: { $0.id == selectedLoadID })
    }

    private var sections: [JournalSection] {
        viewModel.sections(from: loads, week: appState.settings.truckingWeek, locale: AppLocale.locale)
    }

    private var currentWeek: WeekRef {
        appState.settings.truckingWeek.currentWeek()
    }

    var body: some View {
        if showsSplit {
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
        } else if showsInlineSplit {
            HStack(spacing: 0) {
                journalList
                    .frame(minWidth: 320, idealWidth: 400, maxWidth: 440)
                Divider()
                inlineDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            journalList
        }
    }

    @ViewBuilder
    private var inlineDetail: some View {
        if let load = selectedLoad {
            LoadDetailView(load: load)
                .id(load.id)
        } else {
            ContentUnavailableView {
                Label("journal.select.title", systemImage: "list.bullet.rectangle")
            } description: {
                Text("journal.select.message")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .forestBackground()
        }
    }

    private var journalList: some View {
        @Bindable var model = viewModel

        return ScrollViewReader { proxy in
        List {
            Section {
                JournalHomeHeader(
                    name: appState.catalog.profile?.name ?? "",
                    showsTools: horizontalSizeClass != .regular,
                    onAdd: { isAddingLoad = true },
                    onSearch: {
                        isSearching.toggle()
                        if !isSearching { viewModel.searchText = "" }
                    },
                    onTool: { tool = $0 }
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

            if isSearching {
                journalSearch
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                        .id(load.id)
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
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        // iPad sidebar shows the journal as one column; stop cards stretching across 13 inches.
        .padReadable()
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
        // Inline iPad split: the bar carries the selected load's title and edit/delete menu.
        .navigationTitle(showsInlineSplit ? (selectedLoad?.tripId ?? "") : "")
        .toolbar(showsInlineSplit && selectedLoad != nil ? .automatic : .hidden, for: .navigationBar)
        .onAppear {
            revealSharedLoad(using: proxy)
        }
        .onChange(of: appState.highlightedLoadIDs) { _, _ in
            revealSharedLoad(using: proxy)
        }
        .navigationDestination(for: Load.self) { load in
            LoadDetailView(load: load)
        }
        .navigationDestination(item: $tool) { tool in
            JournalToolScreen(tool: tool)
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
        .sheet(isPresented: $showSurveyPaywall) {
            PremiumPaywallSheet(onClose: { showSurveyPaywall = false })
                .environment(appState)
        }
        .confirmationDialog("journal.share", isPresented: $isChoosingShareFormat, titleVisibility: .visible) {
            Button("journal.share.pdf") { queueShare(.pdf) }
            Button("journal.share.text") { queueShare(.text) }
            Button("action.cancel", role: .cancel) {}
        }
        .sheet(item: $shareActivity) { activity in
            ShareSheet(items: activity.items)
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
        return (0..<7).compactMap { offset in
            guard let day = week.calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DateUtils.string(day, format: "EEEEE", locale: AppLocale.locale, calendar: week.calendar)
        }
    }

    private var journalFilter: some View {
        @Bindable var model = viewModel
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Picker("journal.filter", selection: $model.filter) {
                    ForEach(JournalViewModel.Filter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .font(.appCaptionMedium)
                Spacer(minLength: 8)
                Button {
                    isChoosingShareFormat = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.forestText)
                        .minimumHitTarget()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("journal.share")
                .accessibilityIdentifier("journal.share")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    dateChip("journal.filter.all", .all)
                    dateChip("journal.filter.today", .today)
                    dateChip("journal.filter.thisWeek", .thisWeek)
                    dateChip("journal.filter.onDate", .onDate)
                    dateChip("journal.filter.range", .dateRange)
                }
            }
            if model.filter == .onDate || model.filter == .calendarWeek {
                DatePicker("journal.filter.pickDate", selection: $model.selectedDay, displayedComponents: .date)
            }
            if model.filter == .dateRange {
                DatePicker("journal.filter.from", selection: $model.rangeStart, displayedComponents: .date)
                DatePicker("journal.filter.to", selection: $model.rangeEnd, in: model.rangeStart..., displayedComponents: .date)
            }
        }
    }

    private func dateChip(_ key: LocalizedStringKey, _ filter: JournalViewModel.Filter) -> some View {
        let selected = viewModel.filter == filter
        return Button {
            viewModel.filter = filter
            if filter == .today { viewModel.selectedDay = Date() }
        } label: {
            Text(key)
                .font(.appCaptionMedium)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.forestOnPrimary : Color.forestText)
                .background(selected ? AnyShapeStyle(Color.forestPrimary) : AnyShapeStyle(Color.forestSurfaceMuted), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var journalSearch: some View {
        @Bindable var model = viewModel
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.forestTextSecondary)
            TextField("journal.search.prompt", text: $model.searchText)
                .font(.appBody)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.forestTextSecondary)
                }
                .accessibilityLabel("action.clear")
            }
            Button("action.cancel") {
                model.searchText = ""
                isSearching = false
            }
            .font(.appCaptionMedium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.forestSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func revealSharedLoad(using proxy: ScrollViewProxy) {
        guard let id = appState.highlightedLoadIDs.first else { return }
        isSearching = false
        viewModel.searchText = ""
        viewModel.filter = .all
        selectedLoadID = id
        withAnimation {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func loadLink(_ load: Load) -> some View {
        let card = JournalLoadCard(
            load: load,
            thresholds: appState.settings.rpmThresholds,
            onCamera: { cameraLoad = load },
            onScan: { scannerLoad = load }
        )
        return Group {
            if showsSplit || showsInlineSplit {
                Button { selectedLoadID = load.id } label: { card }
            } else {
                NavigationLink(value: load) { card }
            }
        }
        .buttonStyle(.plain)
    }

    /// Lets the action sheet finish dismissing before the system share sheet is presented.
    private func queueShare(_ format: PeriodReportShare.Format) {
        Task { @MainActor in
            await presentShare(format)
        }
    }

    private func presentShare(_ format: PeriodReportShare.Format) async {
        let settings = appState.settings
        let week = settings.truckingWeek
        let now = Date()
        let scope = PeriodReportBuilder.scope(
            home: PeriodReportShare.homePeriod(for: viewModel.filter),
            selectedDay: viewModel.selectedDay,
            now: now,
            week: week
        )
        let request = PeriodReportShare.request(
            scope: scope,
            loads: loads,
            diesel: appState.catalog.diesel,
            expenses: appState.catalog.expenses,
            driverName: appState.catalog.profile?.name ?? "",
            weeklyGoal: settings.weeklyGoal,
            languageCode: AppLocale.resolvedCode(for: settings.language),
            measurementSystem: settings.measurementSystem,
            week: week,
            generatedAt: now
        )
        let prepared = await Task.detached(priority: .userInitiated) {
            PeriodReportShare.prepare(request, format: format)
        }.value
        do {
            shareActivity = try PeriodReportShare.activity(for: prepared)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
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
