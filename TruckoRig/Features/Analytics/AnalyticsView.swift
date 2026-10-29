import Charts
import SwiftUI

/// «Мои цифры»: paycheck and diesel side by side, then routes, weekdays and the weekly line.
struct AnalyticsView: View {

    var showsBackButton: Bool = true

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = AnalyticsViewModel()

    private var page: AnalyticsPage {
        viewModel.page(
            loads: appState.catalog.loads,
            paychecks: appState.catalog.paychecks,
            diesel: appState.catalog.diesel,
            calendar: appState.settings.truckingWeek
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                financeCard
                routesCard
                dailyCard
                weeklyCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .forestBackground()
        .premiumGated("premium.locked.analytics")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        @Bindable var model = viewModel
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if showsBackButton {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.heroText)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("action.back")
                }
                Text("screen.analytics")
                    .font(.appLargeTitle)
                    .foregroundStyle(Color.heroText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("analytics.subtitle")
                .font(.appCallout)
                .foregroundStyle(Color.heroTextMuted)
                .fixedSize(horizontal: false, vertical: true)
            Picker("analytics.period", selection: $model.period) {
                ForEach(AnalyticsViewModel.Period.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroGradient())
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.top, 8)
    }

    private var financeCard: some View {
        let finance = page.finance
        let system = appState.settings.measurementSystem
        return card {
            Text("analytics.finance.title")
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)
            if !finance.hasData {
                Text("analytics.finance.empty")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    financeHeadline(
                        USMoneyFormat.currency(finance.paycheckTotal),
                        "analytics.finance.paycheck",
                        Color.widgetIndigo
                    )
                    financeHeadline(
                        USMoneyFormat.currency(finance.dieselTotal),
                        "analytics.finance.diesel",
                        Color.forestError
                    )
                }
                if finance.dieselGallons > 0 {
                    HStack(alignment: .top, spacing: 12) {
                        financeStat(
                            USMoneyFormat.number(MeasurementUnits.displayVolume(finance.dieselGallons, system: system)),
                            system == .kilometers ? "analytics.finance.liters" : "analytics.finance.gallons"
                        )
                        financeStat(
                            finance.avgPricePerGallon.map {
                                USMoneyFormat.rpm(MeasurementUnits.displayUnitPrice($0, system: system))
                            } ?? "—",
                            system == .kilometers ? "analytics.finance.pricePerLiter" : "analytics.finance.price"
                        )
                    }
                }
                if finance.dieselSavings > 0 {
                    Text(String(localized: "analytics.finance.savings \(USMoneyFormat.currency(finance.dieselSavings))"))
                        .font(.appBody)
                        .foregroundStyle(Color.forestSuccess)
                }
            }
        }
    }

    private var routesCard: some View {
        card {
            Text("analytics.topRoutes")
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)
            if page.routes.isEmpty {
                Text("analytics.empty")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            } else {
                ForEach(page.routes) { route in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.label)
                            .font(.appBodyMedium)
                            .foregroundStyle(Color.forestText)
                            .lineLimit(2)
                        Text(routeDetail(route))
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
            }
        }
    }

    private var dailyCard: some View {
        let maxGross = page.daily.map(\.gross).max() ?? 0
        return card {
            Text("analytics.daily")
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)
            if maxGross <= 0 {
                Text("analytics.empty")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            } else {
                ForEach(page.daily) { day in
                    HStack(spacing: 8) {
                        Text(day.label)
                            .font(.appCaptionMedium)
                            .foregroundStyle(Color.forestTextSecondary)
                            .frame(width: 32, alignment: .leading)
                        GeometryReader { geo in
                            let fraction = maxGross > 0 ? day.gross / maxGross : 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.forestSurfaceMuted)
                                if day.gross > 0 {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.widgetIndigo, Color.widgetIndigo.opacity(0.45)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(8, geo.size.width * fraction))
                                }
                            }
                        }
                        .frame(height: 18)
                        Text(USMoneyFormat.currency(day.gross))
                            .font(.appCaption)
                            .foregroundStyle(Color.forestText)
                            .frame(width: 72, alignment: .trailing)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }

    private var weeklyCard: some View {
        let weeks = page.weeks
        return card {
            Text("analytics.grossByWeek")
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)
            if weeks.allSatisfy({ $0.gross == 0 }) {
                Text("analytics.empty")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            } else {
                Chart(Array(weeks.enumerated()), id: \.offset) { item in
                    let point = item.element
                    AreaMark(
                        x: .value("week", item.offset),
                        y: .value("gross", point.gross)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.widgetIndigo.opacity(0.28), Color.widgetIndigo.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("week", item.offset),
                        y: .value("gross", point.gross)
                    )
                    .foregroundStyle(Color.widgetIndigo)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(
                        x: .value("week", item.offset),
                        y: .value("gross", point.gross)
                    )
                    .foregroundStyle(Color.widgetIndigo)
                    .symbolSize(24)
                }
                .chartXAxis {
                    AxisMarks(values: Array(weeks.indices)) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self), weeks.indices.contains(index) {
                                Text("analytics.weekTick \(weeks[index].week.weekNumber)")
                                    .font(.appCaption)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(USMoneyFormat.currency(amount))
                                    .font(.appCaption)
                            }
                        }
                    }
                }
                .frame(height: 220)
                .accessibilityLabel("analytics.grossByWeek")
            }
        }
    }

    private func routeDetail(_ route: RouteStat) -> String {
        let system = appState.settings.measurementSystem
        let gross = USMoneyFormat.currency(route.gross)
        let miles = USMoneyFormat.miles(route.miles, system: system)
        let rpm = route.miles > 0 ? USMoneyFormat.rpmPerMile(route.ratePerMile, system: system) : "—"
        return "\(gross) · \(miles) · \(rpm)"
    }

    private func financeHeadline(_ value: String, _ title: LocalizedStringKey, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.appNumberLarge)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func financeStat(_ value: String, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)
            Text(title)
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.forestCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
