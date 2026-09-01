import MapKit
import SwiftData
import SwiftUI

/// One pin on the route map.
struct RoutePin: Identifiable, Hashable {
    let id: UUID
    let title: String
    let subtitle: String
    let type: StopType
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: RoutePin, rhs: RoutePin) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Pickups and deliveries of a load, or of the most recent load when opened from the sidebar.
struct RouteMapView: View {

    var load: Load? = nil

    @Environment(AppState.self) private var appState
    @Query(sort: \Load.date, order: .reverse) private var loads: [Load]

    @State private var pins: [RoutePin] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var isResolving = false

    private var subject: Load? { load ?? loads.first }

    var body: some View {
        Map(position: $position) {
            ForEach(pins) { pin in
                Annotation(pin.title, coordinate: pin.coordinate) {
                    VStack(spacing: 2) {
                        Image(systemName: pin.type == .pickup ? "shippingbox.fill" : "flag.checkered")
                            .padding(8)
                            .background(pin.type == .pickup ? Color.forestPrimary : Color.forestAccent, in: Circle())
                            .foregroundStyle(Color.forestOnPrimary)
                        Text(pin.subtitle)
                            .font(.appCaption)
                            .foregroundStyle(Color.forestText)
                    }
                    .accessibilityLabel("\(pin.title), \(pin.subtitle)")
                }
            }

            if pins.count > 1 {
                MapPolyline(coordinates: pins.map(\.coordinate))
                    .stroke(Color.forestSecondary, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay(alignment: .top) {
            if let subject {
                routeSummary(subject)
            }
        }
        .overlay {
            if pins.isEmpty && !isResolving {
                EmptyStateView(
                    systemImage: "map",
                    title: "map.empty.title",
                    message: "map.empty.message"
                )
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
                .padding(Spacing.section)
            }
        }
        .navigationTitle("screen.map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StateHeatmapView()
                } label: {
                    Label("map.heatmap", systemImage: "square.grid.3x3.fill")
                }
            }
        }
        .task(id: subject?.id) {
            await resolvePins()
        }
    }

    private func routeSummary(_ load: Load) -> some View {
        SoftCard(padding: 12) {
            Text(load.route)
                .font(.appBodyMedium)
            Text("\(load.tripId) · \(Formatters.miles(load.totalMiles))")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
        .padding(Spacing.standard)
    }

    /// Resolves each stop to a coordinate.
    ///
    /// Geocoding is best-effort and rate limited by the system, so a stop that cannot be resolved
    /// falls back to its state centroid rather than dropping off the map.
    private func resolvePins() async {
        guard let subject else {
            pins = []
            return
        }
        isResolving = true
        defer { isResolving = false }

        var resolved: [RoutePin] = []
        for stop in subject.sortedStops {
            let coordinate = await GeoUtils.geocode(cityState: stop.cityState)
                ?? GeoUtils.coordinate(forState: stop.state)
            guard let coordinate else { continue }
            resolved.append(
                RoutePin(
                    id: stop.id,
                    title: stop.cityState,
                    subtitle: stop.type.shortLabel,
                    type: stop.type,
                    coordinate: coordinate
                )
            )
        }

        pins = resolved
        if let region = GeoUtils.region(fitting: resolved.map(\.coordinate)) {
            position = .region(region)
        }
    }
}
