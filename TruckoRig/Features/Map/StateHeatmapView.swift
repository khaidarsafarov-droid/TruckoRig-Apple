import MapKit
import SwiftData
import SwiftUI

/// Where the money comes from: one marker per state, sized by gross and coloured by rate per mile.
struct StateHeatmapView: View {

    @Environment(AppState.self) private var appState
    @Query(sort: \Load.date, order: .reverse) private var loads: [Load]

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 34, longitudeDelta: 46)
        )
    )
    @State private var selected: StateRevenue?

    private var revenue: [StateRevenue] {
        AnalyticsCalculator.stateRevenue(loads: loads.map(\.summary))
    }

    private var maxGross: Double {
        max(1, revenue.first?.gross ?? 1)
    }

    var body: some View {
        Map(position: $position) {
            ForEach(revenue) { entry in
                if let coordinate = GeoUtils.coordinate(forState: entry.state) {
                    Annotation(entry.state, coordinate: coordinate) {
                        marker(entry)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let selected {
                detailCard(selected)
            } else {
                legend
            }
        }
        .overlay {
            if revenue.isEmpty {
                EmptyStateView(
                    systemImage: "map",
                    title: "heatmap.empty.title",
                    message: "heatmap.empty.message"
                )
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
                .padding(Spacing.section)
            }
        }
        .navigationTitle("map.heatmap")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func marker(_ entry: StateRevenue) -> some View {
        let band = RPMCalculator.band(for: entry.ratePerMile, thresholds: appState.settings.rpmThresholds)
        // Area, not diameter, scales with gross so a big state does not swamp the map.
        let diameter = 22 + 26 * (entry.gross / maxGross).squareRoot()

        return Button {
            selected = selected?.state == entry.state ? nil : entry
        } label: {
            Text(entry.state)
                .font(.appCaption)
                .foregroundStyle(Color.forestOnPrimary)
                .frame(width: diameter, height: diameter)
                .background(band.tint.opacity(0.85), in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        Color.forestOnPrimary.opacity(selected?.state == entry.state ? 1 : 0),
                        lineWidth: 2
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel((USStates.name(code: entry.state) ?? entry.state) + ", " + Formatters.money(entry.gross))
    }

    private func detailCard(_ entry: StateRevenue) -> some View {
        SoftCard {
            SectionHeader(title: "heatmap.state")
            Text(USStates.name(code: entry.state) ?? entry.state)
                .font(.appHeadline)
            HStack {
                StatTile(title: "stat.gross", value: Formatters.money(entry.gross))
                StatTile(title: "stat.miles", value: Formatters.miles(entry.miles))
                StatTile(
                    title: "stat.rpm",
                    value: Formatters.ratePerMile(entry.ratePerMile),
                    tint: RPMCalculator.band(for: entry.ratePerMile, thresholds: appState.settings.rpmThresholds).tint
                )
                StatTile(title: "stat.loads", value: "\(entry.loadCount)")
            }
        }
        .padding(Spacing.standard)
    }

    private var legend: some View {
        HStack(spacing: Spacing.standard) {
            legendItem(.good, "heatmap.legend.good")
            legendItem(.acceptable, "heatmap.legend.ok")
            legendItem(.low, "heatmap.legend.low")
        }
        .padding(12)
        .background(.thinMaterial, in: Capsule())
        .padding(Spacing.standard)
    }

    private func legendItem(_ band: RPMBand, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Circle().fill(band.tint).frame(width: 10, height: 10)
            Text(title)
                .font(.appCaption)
                .foregroundStyle(Color.forestText)
        }
    }
}
