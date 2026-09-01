import Charts
import SwiftData
import SwiftUI

/// Gross over time, best states and best lanes.
struct AnalyticsView: View {

    @Environment(AppState.self) private var appState
    @Query(sort: \Load.date, order: .reverse) private var loads: [Load]
    @State private var viewModel = AnalyticsViewModel()

    private var calendar: TruckingWeek { appState.settings.truckingWeek }

    var body: some View {
        @Bindable var model = viewModel

        ScrollView {
            LazyVStack(spacing: Spacing.section) {
                Picker("analytics.range", selection: $model.range) {
                    ForEach(AnalyticsViewModel.Range.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                totalsCard
                grossChartCard
                statesCard
                routesCard
            }
            .padding(Spacing.standard)
        }
        .forestBackground()
        .navigationTitle("screen.analytics")
    }

    private var totalsCard: some View {
        let totals = viewModel.totals(from: loads, calendar: calendar)
        return SoftCard {
            HStack {
                StatTile(title: "stat.gross", value: Formatters.money(totals.totalRate))
                StatTile(title: "stat.miles", value: Formatters.miles(totals.totalMiles))
                StatTile(
                    title: "stat.rpm",
                    value: Formatters.ratePerMile(totals.ratePerMile),
                    tint: RPMCalculator.band(for: totals.ratePerMile, thresholds: appState.settings.rpmThresholds).tint
                )
                StatTile(title: "stat.loads", value: "\(totals.loadCount)")
            }
        }
    }

    private var grossChartCard: some View {
        let series = viewModel.weeklySeries(from: loads, calendar: calendar)
        return SoftCard {
            SectionHeader(title: "analytics.grossByWeek")
            if series.allSatisfy({ $0.gross == 0 }) {
                Text("analytics.empty")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            } else {
                Chart(series) { point in
                    BarMark(
                        x: .value(String(localized: "analytics.axis.week"), "W\(point.week.weekNumber)"),
                        y: .value(String(localized: "stat.gross"), point.gross)
                    )
                    .foregroundStyle(Color.forestPrimary)
                    .cornerRadius(4)

                    if appState.settings.weeklyGoal > 0 {
                        RuleMark(y: .value(String(localized: "goal.target"), appState.settings.weeklyGoal))
                            .foregroundStyle(Color.forestAccent)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(Formatters.money(amount))
                            }
                        }
                    }
                }
                .frame(height: 200)
                .accessibilityLabel("analytics.grossByWeek")
            }
        }
    }

    private var statesCard: some View {
        let states = viewModel.stateRevenue(from: loads, calendar: calendar).prefix(8)
        return SoftCard {
            SectionHeader(title: "analytics.byState")
            if states.isEmpty {
                Text("analytics.empty")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            } else {
                Chart(Array(states)) { entry in
                    BarMark(
                        x: .value(String(localized: "stat.gross"), entry.gross),
                        y: .value(String(localized: "analytics.axis.state"), entry.state)
                    )
                    .foregroundStyle(RPMCalculator.band(for: entry.ratePerMile, thresholds: appState.settings.rpmThresholds).tint)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(Formatters.money(amount))
                            }
                        }
                    }
                }
                .frame(height: CGFloat(states.count) * 28 + 20)

                NavigationLink {
                    StateHeatmapView()
                } label: {
                    Label("analytics.openHeatmap", systemImage: "map")
                        .font(.appCaptionMedium)
                }
            }
        }
    }

    private var routesCard: some View {
        let routes = viewModel.topRoutes(from: loads, calendar: calendar)
        return SoftCard {
            SectionHeader(title: "analytics.topRoutes")
            if routes.isEmpty {
                Text("analytics.empty")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            } else {
                ForEach(routes) { route in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.label)
                                .font(.appBody)
                            Text("analytics.route.detail \(route.loadCount) \(Formatters.ratePerMile(route.ratePerMile))")
                                .font(.appCaption)
                                .foregroundStyle(Color.forestTextSecondary)
                        }
                        Spacer()
                        Text(Formatters.money(route.gross))
                            .font(.appCaptionMedium)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
