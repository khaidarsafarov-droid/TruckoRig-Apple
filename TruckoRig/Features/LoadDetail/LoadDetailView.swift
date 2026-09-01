import SwiftData
import SwiftUI

/// Full trip card: route, money, stops, penalties and attached media.
struct LoadDetailView: View {

    let load: Load

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private var band: RPMBand {
        RPMCalculator.band(for: load.ratePerMile, thresholds: appState.settings.rpmThresholds)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.section) {
                headerCard
                stopsCard
                if !(load.penalties ?? []).isEmpty { penaltiesCard }
                if load.isDispute { disputeCard }
                mediaCard
                if let rawMessage = load.rawMessage?.nonEmpty { sourceCard(rawMessage) }
            }
            .padding(Spacing.standard)
        }
        .forestBackground()
        .navigationTitle(load.tripId)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isEditing = true } label: {
                        Label("action.edit", systemImage: "pencil")
                    }
                    NavigationLink {
                        RouteMapView(load: load)
                    } label: {
                        Label("screen.map", systemImage: "map")
                    }
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Label("action.delete", systemImage: "trash")
                    }
                } label: {
                    Label("action.more", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditLoadView(load: load)
        }
        .confirmationDialog("journal.delete.confirm", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("action.delete", role: .destructive) { delete() }
            Button("action.cancel", role: .cancel) {}
        }
        .alert(
            "error.title",
            isPresented: .constant(errorMessage != nil),
            actions: { Button("action.ok") { errorMessage = nil } },
            message: { Text(errorMessage ?? "") }
        )
    }

    // MARK: - Cards

    private var headerCard: some View {
        SoftCard {
            Text(load.route)
                .font(.appTitle)
                .foregroundStyle(Color.forestText)

            Text(DateUtils.weekdayShortDay(load.date))
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)

            Divider().padding(.vertical, 4)

            HStack {
                StatTile(title: "stat.gross", value: Formatters.moneyPrecise(load.totalRate))
                StatTile(title: "stat.miles", value: Formatters.miles(load.totalMiles))
                StatTile(title: "stat.rpm", value: Formatters.ratePerMile(load.ratePerMile), tint: band.tint)
            }

            HStack {
                StatTile(title: "stat.duration", value: DateUtils.durationDays(load.durationDays))
                StatTile(
                    title: "stat.pace",
                    value: Formatters.perDay(LoadYieldCalculator.pace(of: load.summary))
                )
                StatTile(title: "stat.stops", value: "\(load.stopCount)")
            }
        }
    }

    private var stopsCard: some View {
        SoftCard {
            SectionHeader(title: "load.stops")
            ForEach(load.sortedStops) { stop in
                HStack(alignment: .top, spacing: Spacing.tight) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(stop.type == .pickup ? Color.forestPrimary : Color.forestAccent)
                            .frame(width: 10, height: 10)
                        if stop.id != load.sortedStops.last?.id {
                            Rectangle()
                                .fill(Color.forestSeparator)
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(minHeight: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.cityState)
                            .font(.appBodyMedium)
                            .foregroundStyle(Color.forestText)
                        if let facility = stop.facility {
                            Text(facility)
                                .font(.appCaption)
                                .foregroundStyle(Color.forestTextSecondary)
                        }
                        if let scheduled = stop.scheduledTime {
                            Text(DateUtils.dateTime(scheduled))
                                .font(.appCaption)
                                .foregroundStyle(Color.forestTextSecondary)
                        }
                        if let note = stop.note {
                            Text(note)
                                .font(.appCaption)
                                .foregroundStyle(Color.forestTextSecondary)
                        }
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var penaltiesCard: some View {
        SoftCard {
            SectionHeader(title: "load.penalties")
            ForEach(load.penalties ?? []) { penalty in
                HStack {
                    Text(penalty.summary)
                        .font(.appBody)
                    Spacer()
                    Text(Formatters.moneyPrecise(-penalty.amount))
                        .font(.appCaptionMedium)
                        .foregroundStyle(Color.forestError)
                }
            }
            Divider()
            HStack {
                Text("load.net")
                    .font(.appCaptionMedium)
                Spacer()
                Text(Formatters.moneyPrecise(load.summary.netRate))
                    .font(.appNumber)
            }
        }
    }

    private var disputeCard: some View {
        SoftCard {
            SectionHeader(title: "load.dispute")
            Label(
                load.disputeCompleted ? "load.dispute.completed" : "load.dispute.open",
                systemImage: load.disputeCompleted ? "checkmark.seal" : "clock"
            )
            .font(.appBody)
            .foregroundStyle(load.disputeCompleted ? Color.forestSuccess : Color.forestWarning)

            if let amount = load.disputeAmount {
                LabeledContent("load.dispute.amount") {
                    Text(Formatters.moneyPrecise(amount))
                }
            }
            if let responseDate = load.disputeResponseDate {
                LabeledContent("load.dispute.responseDate") {
                    Text(DateUtils.mediumDate(responseDate))
                }
            }
        }
    }

    private var mediaCard: some View {
        SoftCard {
            SectionHeader(title: "load.media")
            let photos = load.photos ?? []
            let scans = load.scans ?? []

            if photos.isEmpty && scans.isEmpty {
                Text("load.media.empty")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            } else {
                NavigationLink {
                    GalleryView(load: load)
                } label: {
                    Label("load.media.count \(photos.count) \(scans.count)", systemImage: "photo.on.rectangle")
                        .font(.appBody)
                }
            }

            HStack(spacing: Spacing.tight) {
                NavigationLink {
                    CameraView(load: load)
                } label: {
                    Label("screen.camera", systemImage: "camera")
                        .font(.appCaptionMedium)
                }
                Spacer()
                NavigationLink {
                    ScannerView(load: load)
                } label: {
                    Label("screen.scanner", systemImage: "doc.viewfinder")
                        .font(.appCaptionMedium)
                }
            }
            .padding(.top, 4)
        }
    }

    private func sourceCard(_ rawMessage: String) -> some View {
        SoftCard {
            DisclosureGroup {
                Text(rawMessage)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                    .textSelection(.enabled)
            } label: {
                Text("load.source")
                    .font(.appHeadline)
            }
        }
    }

    private func delete() {
        let repository = LoadRepository(
            context: modelContext,
            sync: appState.sync,
            week: appState.settings.truckingWeek
        )
        do {
            try repository.delete(load)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
