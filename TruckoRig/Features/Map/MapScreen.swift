import SwiftUI

/// Geographic efficiency: outbound RPM by origin state. Port of Android `MapScreen`.
struct MapScreen: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if !appState.premium.didRefresh {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !appState.premium.isActive {
                MapPremiumLock()
            } else {
                MapScreenBody()
            }
        }
        .forestBackground()
        .navigationTitle("map.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MapPremiumLock: View {
    @Environment(AppState.self) private var appState
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            Text("premium.locked.map")
                .font(.appBody)
                .foregroundStyle(Color.forestText)
            Button("premium.subscribe") { showPaywall = true }
                .buttonStyle(.softPrimary)
        }
        .padding(Spacing.standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallSheet(onClose: { showPaywall = false })
                .environment(appState)
        }
    }
}

private struct MapScreenBody: View {
    @Environment(AppState.self) private var appState
    @Environment(\.locale) private var locale

    @State private var period: MapPeriod = .week
    @State private var selectedCode = MapSelection.resolved(
        UserDefaults.standard.string(forKey: MapSelection.storageKey)
    )
    @State private var yearReports: [CrowdRateReport] = []
    @State private var loadedAt: Int64 = 0
    @State private var snapshot = MapSnapshot.empty
    @State private var isLoading = true
    @State private var fullscreen = false
    @State private var outlines: [StatePolygon] = []

    private var loads: [Load] { appState.catalog.loads }

    private var loadSignature: String {
        loads.map { load in
            "\(load.id.uuidString)|\(load.updatedAt.timeIntervalSince1970)|\(load.totalRate)|\(load.totalMiles)|\(load.pointA ?? "")|\(load.pointB ?? "")"
        }.joined(separator: ";")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        periodSelector
                        metaRow
                        hint
                        MapHeatmapCard(
                            snapshot: snapshot,
                            outlines: outlines,
                            locale: locale,
                            zoom: MapCamera.cardZoom,
                            showsExpand: true,
                            onSelect: select,
                            onExpand: { fullscreen = true }
                        )
                        .frame(height: 480)
                        summary
                        lanes
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .task(id: loadSignature) {
            await reload()
        }
        .task {
            if outlines.isEmpty {
                outlines = StateOutlineLoader.load()
            }
        }
        .fullScreenCover(isPresented: $fullscreen) {
            MapFullscreenCover(
                snapshot: snapshot,
                outlines: outlines,
                locale: locale,
                onSelect: select,
                onClose: { fullscreen = false }
            )
        }
    }

    private var periodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MapPeriod.allCases, id: \.self) { item in
                    MapChip(title: periodTitle(item), selected: item == period) {
                        setPeriod(item)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var metaRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "truck.box")
                .foregroundStyle(Color.forestPrimary)
            Text(subtitle(snapshot))
                .font(.appBody)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private var hint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(Color.forestTextSecondary)
                .padding(.top, 2)
            Text("map.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let summary = snapshot.stateSummary, !summary.stateCode.isEmpty {
            labeledTitle("mappin.circle", text: String(localized: "map.state.header \(stateName(summary.stateCode)) \(summary.stateCode)"))
            labeledBody(
                "speedometer",
                text: String(localized: "map.state.avg \(rpm(summary.avgOutboundRpm.dollars)) \(summary.outboundTrips)")
            )
            labeledTitle("clock", text: String(localized: "map.recent.title"))
            if summary.recent.isEmpty {
                Text(emptyRecent(snapshot.period))
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                    .padding(.leading, 26)
            } else {
                ForEach(summary.recent, id: \.id) { report in
                    recentRow(report)
                }
            }
        }
    }

    @ViewBuilder
    private var lanes: some View {
        if !snapshot.topLanes.isEmpty, snapshot.selectedCode.isEmpty {
            labeledTitle("chart.line.uptrend.xyaxis", text: lanesTitle(snapshot.period))
            ForEach(Array(snapshot.topLanes.enumerated()), id: \.offset) { _, lane in
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "truck.box")
                        .font(.caption)
                        .foregroundStyle(Color.forestTextSecondary)
                    Text(String(localized: "map.lane \(lane.fromState) \(lane.toState) \(rpm(lane.avgRpm.dollars)) \(lane.tripCount)"))
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
            }
        }
    }

    private func recentRow(_ report: CrowdRateReport) -> some View {
        let age = ageText(now: loadedAt, reportedAt: report.reportedAtMillis)
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(Color.forestTextSecondary)
            Text(String(localized: "map.recent \(report.fromState) \(report.toState) \(rpm(report.rpm.dollars)) \(age)"))
                .font(.appBody)
                .foregroundStyle(Color.forestText)
        }
        .padding(.vertical, 2)
    }

    private func labeledTitle(_ symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Color.forestPrimary)
            Text(text)
                .font(.appCallout.weight(.semibold))
                .foregroundStyle(Color.forestText)
        }
    }

    private func labeledBody(_ symbol: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Color.forestTextSecondary)
            Text(text)
                .font(.appBody)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private func reload() async {
        isLoading = true
        let inputs = MapLoadAdapter.inputs(from: loads)
        let now = MapLoadAdapter.nowMillis()
        let reports = await Task.detached(priority: .userInitiated) {
            MapSession.cachedReports(loads: inputs, nowMillis: now)
        }.value
        yearReports = reports
        loadedAt = now
        snapshot = MapSession.apply(
            reports: reports,
            selectedCode: selectedCode,
            period: period,
            nowMillis: now
        )
        isLoading = false
    }

    private func setPeriod(_ next: MapPeriod) {
        guard next != period else { return }
        period = next
        guard !isLoading else { return }
        snapshot = MapSession.apply(
            reports: yearReports,
            selectedCode: selectedCode,
            period: next,
            nowMillis: loadedAt
        )
    }

    private func select(_ code: String) {
        selectedCode = code
        UserDefaults.standard.set(code, forKey: MapSelection.storageKey)
        guard !isLoading else { return }
        snapshot = MapSession.apply(
            reports: yearReports,
            selectedCode: code,
            period: period,
            nowMillis: loadedAt
        )
    }

    private func stateName(_ code: String) -> String {
        if code == "PR" { return "Puerto Rico" }
        return USStates.name(code: code) ?? code
    }

    private func rpm(_ dollars: Double) -> String {
        MapNumberFormat.rpm(dollars, locale: locale)
    }

    private func periodTitle(_ period: MapPeriod) -> LocalizedStringKey {
        switch period {
        case .week: return "map.period.week"
        case .month: return "map.period.month"
        case .year: return "map.period.year"
        }
    }

    private func subtitle(_ snapshot: MapSnapshot) -> String {
        switch snapshot.period {
        case .week: return String(localized: "map.subtitle.week \(snapshot.tripCount)")
        case .month: return String(localized: "map.subtitle.month \(snapshot.tripCount)")
        case .year: return String(localized: "map.subtitle.year \(snapshot.tripCount)")
        }
    }

    private func emptyRecent(_ period: MapPeriod) -> LocalizedStringKey {
        switch period {
        case .week: return "map.recent.empty.week"
        case .month: return "map.recent.empty.month"
        case .year: return "map.recent.empty.year"
        }
    }

    private func lanesTitle(_ period: MapPeriod) -> String {
        switch period {
        case .week: return String(localized: "map.lanes.week")
        case .month: return String(localized: "map.lanes.month")
        case .year: return String(localized: "map.lanes.year")
        }
    }

    private func ageText(now: Int64, reportedAt: Int64) -> String {
        switch CrowdAge.classify(ageMs: now - reportedAt) {
        case .minutes(let count): return String(localized: "map.age.minutes \(count)")
        case .hours(let count): return String(localized: "map.age.hours \(count)")
        case .days(let count): return String(localized: "map.age.days \(count)")
        }
    }
}

private struct MapFullscreenCover: View {
    var snapshot: MapSnapshot
    var outlines: [StatePolygon]
    var locale: Locale
    var onSelect: (String) -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapHeatmapCard(
                snapshot: snapshot,
                outlines: outlines,
                locale: locale,
                zoom: MapCamera.fullscreenZoom,
                showsExpand: false,
                onSelect: onSelect,
                onExpand: {}
            )
            .padding(8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.forestText)
                    .frame(width: 44, height: 44)
                    .background(Color.forestCard.faded(to: 0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("map.close")
            .padding(16)
        }
        .background(Color.forestBackground.ignoresSafeArea())
    }
}

/// The map card: polygons, legend, state chips, and the selected-state figures.
private struct MapHeatmapCard: View {
    var snapshot: MapSnapshot
    var outlines: [StatePolygon]
    var locale: Locale
    var zoom: Float
    var showsExpand: Bool
    var onSelect: (String) -> Void
    var onExpand: () -> Void

    private var painted: [PaintedStatePolygon] {
        StateHeatmapPainter.paint(
            rings: outlines,
            metrics: snapshot.metrics,
            selectedCode: snapshot.selectedCode
        )
    }

    private var selected: USStateMetric? {
        guard !snapshot.selectedCode.isEmpty else { return nil }
        return snapshot.metrics.first { $0.code == snapshot.selectedCode }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                mapCanvas
                if showsExpand {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.forestText)
                            .frame(width: 36, height: 36)
                            .background(Color.forestCard.faded(to: 0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .accessibilityLabel("map.expand")
                    .padding(4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            legend
            chips
            if let selected {
                detail(selected)
            }
        }
        .padding(12)
        .background(Color.forestCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var mapCanvas: some View {
        if GoogleMapsSession.prepare(apiKey: MapsRuntimeKey.current) {
            GoogleHeatmapMap(polygons: painted, zoom: zoom, onSelect: onSelect)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ContentUnavailableView {
                Label("map.key.missing", systemImage: "map")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.forestSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                legendChip("map.rating.good", Color.successContainer, Color.forestSuccess)
                legendChip("map.rating.low", Color.dangerContainer, Color.forestError)
                legendChip("map.rating.neutral", Color.warningContainer, Color.forestText)
                legendChip("map.rating.none", Color(hex: "E2E8F0"), Color.forestTextSecondary)
            }
        }
    }

    private func legendChip(_ title: LocalizedStringKey, _ fill: Color, _ ink: Color) -> some View {
        Text(title)
            .font(.appCaptionMedium)
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                MapChip(title: "map.reset", selected: snapshot.selectedCode.isEmpty) {
                    onSelect("")
                }
                ForEach(CrowdMapAggregator.chipCodes(snapshot.metrics), id: \.self) { code in
                    MapChip(title: LocalizedStringKey(code), selected: code == snapshot.selectedCode) {
                        onSelect(code)
                    }
                }
            }
        }
    }

    private func detail(_ state: USStateMetric) -> some View {
        let name = stateName(state.code)
        let rpmText = state.trips > 0 ? MapNumberFormat.rpm(state.revenuePerMile, locale: locale) : "—"
        let gross = MapNumberFormat.gross(state.revenue, locale: locale)
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "map.detail.trips \(name) \(state.code) \(state.trips)"))
                .font(.appBodyMedium)
                .foregroundStyle(Color.forestText)
            Text(String(localized: "map.detail.rpm \(rpmText)"))
                .font(.appBody)
                .foregroundStyle(Color.forestTextSecondary)
            Text(String(localized: "map.detail.gross \(gross)"))
                .font(.appBody)
                .foregroundStyle(Color.forestTextSecondary)
            Text(String(localized: "map.detail.rating \(ratingLabel(state.rating))"))
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestTextSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.forestBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stateName(_ code: String) -> String {
        if code == "PR" { return "Puerto Rico" }
        return USStates.name(code: code) ?? code
    }

    private func ratingLabel(_ rating: StateRating) -> String {
        switch rating {
        case .good: return String(localized: "map.rating.good")
        case .bad: return String(localized: "map.rating.bad")
        case .neutral: return String(localized: "map.rating.neutral")
        case .noData: return String(localized: "map.rating.none")
        }
    }
}

private struct MapChip: View {
    var title: LocalizedStringKey
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.appCaptionMedium)
                .foregroundStyle(selected ? Color.forestOnPrimary : Color.forestText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    selected ? AnyShapeStyle(Color.forestPrimary) : AnyShapeStyle(Color.forestSurfaceMuted),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

private enum MapNumberFormat {
    static func rpm(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "0.00"
    }

    static func gross(_ value: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }
}

enum StateOutlineLoader {
    static func load(bundle: Bundle = .main) -> [StatePolygon] {
        guard let url = bundle.url(forResource: "us_states", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return StateOutlineParser.rings(from: data)
    }
}
