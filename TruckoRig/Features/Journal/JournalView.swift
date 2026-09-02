import SwiftData
import SwiftUI

/// Home screen: every trip, newest week first.
struct JournalView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Load.date, order: .reverse) private var loads: [Load]

    @State private var viewModel = JournalViewModel()
    @State private var isAddingLoad = false

    private var sections: [JournalSection] {
        viewModel.sections(from: loads, week: appState.settings.truckingWeek)
    }

    var body: some View {
        @Bindable var model = viewModel

        List {
            if !loads.isEmpty {
                summaryHeader
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.loads) { load in
                        NavigationLink(value: load) {
                            LoadRowView(load: load, thresholds: appState.settings.rpmThresholds)
                        }
                        .listRowBackground(Color.forestCard)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.loadPendingDeletion = load
                            } label: {
                                Label("action.delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    WeekHeaderView(section: section)
                }
            }

            if loads.isEmpty {
                emptyState
            } else if sections.isEmpty {
                noResultsState
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle("tab.journal")
        .navigationDestination(for: Load.self) { load in
            LoadDetailView(load: load)
        }
        .searchable(text: $model.searchText, prompt: Text("journal.search.prompt"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                filterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingLoad = true
                } label: {
                    Label("journal.addLoad", systemImage: "plus")
                }
                .accessibilityLabel("journal.addLoad")
            }
        }
        .sheet(isPresented: $isAddingLoad) {
            AddLoadView()
                .presentationDetents([.large])
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

    private var summaryHeader: some View {
        let totals = viewModel.visibleTotals(from: loads)
        return Section {
            HStack {
                StatTile(title: "stat.gross", value: Formatters.money(totals.totalRate))
                StatTile(title: "stat.miles", value: Formatters.miles(totals.totalMiles))
                StatTile(
                    title: "stat.rpm",
                    value: Formatters.ratePerMile(totals.ratePerMile),
                    tint: RPMCalculator.band(for: totals.ratePerMile, thresholds: appState.settings.rpmThresholds).tint
                )
            }
        }
        .listRowBackground(Color.forestCard)
    }

    private var filterMenu: some View {
        @Bindable var model = viewModel
        return Menu {
            Picker("journal.filter", selection: $model.filter) {
                ForEach(JournalViewModel.Filter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
        } label: {
            Label("journal.filter", systemImage: viewModel.filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
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
    }

    private var noResultsState: some View {
        EmptyStateView(
            systemImage: "magnifyingglass",
            title: "journal.noResults.title",
            message: "journal.noResults.message"
        )
        .listRowBackground(Color.clear)
    }

    private func deletePending() {
        guard let load = viewModel.loadPendingDeletion else { return }
        viewModel.loadPendingDeletion = nil
        let repository = appState.loadRepository(in: modelContext)
        do {
            try repository.delete(load)
        } catch {
            viewModel.errorMessage = error.localizedDescription
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
