import SwiftUI

/// Widget Camera / Scan opens this list first so the file is attached to a trip.
///
/// Quick picks are the current trucking week, newest first, capped at three. The driver can
/// search the rest of the journal. Port of `AttachLoadPickScreen`.
struct AttachLoadPickView: View {

    enum Mode {
        case camera
        case scanner
    }

    var mode: Mode

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var browseAll = false
    @State private var query = ""
    @State private var chosen: Load?

    private var week: WeekRef { appState.settings.truckingWeek.currentWeek() }

    private var candidates: [AttachLoadCandidate] {
        appState.catalog.loads.map { $0.attachCandidate() }
    }

    private var quick: [AttachLoadCandidate] {
        AttachLoadSelection.quickPickThisWeek(
            loads: candidates,
            weekNumber: week.weekNumber,
            year: week.year
        )
    }

    private var browsed: [AttachLoadCandidate] {
        AttachLoadSelection.filterBrowse(loads: candidates, query: query)
    }

    private var displayed: [AttachLoadCandidate] { browseAll ? browsed : quick }

    var body: some View {
        Group {
            if let chosen {
                switch mode {
                case .camera:
                    CameraView(load: chosen)
                case .scanner:
                    ScannerView(load: chosen)
                }
            } else {
                picker
            }
        }
    }

    private var picker: some View {
        List {
            if displayed.isEmpty && !browseAll {
                empty
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    Text(hint)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                        .listRowBackground(Color.clear)
                    if browseAll {
                        TextField("attach.search", text: $query)
                    }
                    if displayed.isEmpty {
                        Text("attach.searchEmpty")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                    ForEach(displayed, id: \.id) { candidate in
                        Button {
                            chosen = appState.catalog.loads.first { $0.id.uuidString == candidate.id }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.tripId)
                                    .font(.appCaptionMedium)
                                    .foregroundStyle(Color.forestTextSecondary)
                                Text(candidate.route.isEmpty ? candidate.date : candidate.route)
                                    .font(.appBodyMedium)
                                    .foregroundStyle(Color.forestText)
                                Text(candidate.date)
                                    .font(.appCaption)
                                    .foregroundStyle(Color.forestTextSecondary)
                            }
                        }
                    }
                }
                if !browseAll {
                    Section {
                        Button("attach.browseAll") { browseAll = true }
                        Button("journal.addLoad") { dismiss() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle(browseAll ? "attach.browseTitle" : "attach.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel") {
                    if browseAll {
                        browseAll = false
                        query = ""
                    } else if chosen != nil {
                        chosen = nil
                    } else {
                        dismiss()
                    }
                }
            }
        }
    }

    private var hint: String {
        if browseAll { return String(localized: "attach.browseHint") }
        switch mode {
        case .camera: return String(localized: "attach.cameraHint")
        case .scanner: return String(localized: "attach.scannerHint")
        }
    }

    @ViewBuilder
    private var empty: some View {
        if candidates.isEmpty {
            EmptyStateView(
                systemImage: "doc.text",
                title: "attach.empty",
                message: "attach.emptyHint",
                actionTitle: "journal.addLoad",
                action: { dismiss() }
            )
        } else {
            VStack(spacing: Spacing.standard) {
                EmptyStateView(
                    systemImage: "calendar",
                    title: "attach.emptyWeek",
                    message: "attach.emptyWeekHint",
                    actionTitle: "attach.browseAll",
                    action: { browseAll = true }
                )
                Button("journal.addLoad") { dismiss() }
                    .buttonStyle(.softSecondary)
            }
        }
    }
}
