import SwiftUI

/// Scrolling home header: brand, greeting, and the on-device badge.
struct JournalHomeHeader: View {
    let name: String
    var onAdd: () -> Void
    var onSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                headerButton("plus", label: "journal.addLoad", identifier: "journal.addLoad", action: onAdd)
                Spacer()
                headerButton("magnifyingglass", label: "home.cd.search", action: onSearch)
            }

            Text("home.brand")
                .font(.appLargeTitle)
                .foregroundStyle(Color.forestText)
                .allowsHitTesting(false)

            Text(greeting)
                .font(.appBody)
                .foregroundStyle(Color.forestTextSecondary)

            Label("home.privacy", systemImage: "lock.fill")
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.forestSurfaceMuted, in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let trimmed = name.trimmed
        if trimmed.isEmpty {
            switch hour {
            case ..<12: return String(localized: "home.greeting.morning.plain")
            case ..<17: return String(localized: "home.greeting.afternoon.plain")
            default: return String(localized: "home.greeting.evening.plain")
            }
        }
        switch hour {
            case ..<12: return String(localized: "home.greeting.morning \(trimmed)")
            case ..<17: return String(localized: "home.greeting.afternoon \(trimmed)")
            default: return String(localized: "home.greeting.evening \(trimmed)")
        }
    }

    private func headerButton(
        _ symbol: String,
        label: LocalizedStringKey,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.forestText)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel(label)
        .modifier(ActionIdentifier(identifier: identifier))
    }
}

/// Current-week card: gross, goal ring, weekday dots, RPM / miles / loads.
struct HomeWeekHeroCard: View {
    let weekNumber: Int
    let rangeCaption: String
    let gross: Double
    let goal: Double
    let percent: Double
    let rpmText: String
    let milesText: String
    var measurementSystem: MeasurementSystem = .miles
    let loadCount: Int
    let dayLabels: [String]
    let elapsedDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "home.week.chip \(weekNumber) \(rangeCaption)"))
                .font(.appCallout)
                .foregroundStyle(Color.heroTextMuted)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(USMoneyFormat.currency(gross))
                        .font(.appNumberLarge)
                        .foregroundStyle(Color.heroText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if goal > 0 {
                        Text(String(localized: "home.week.ofGoal \(USMoneyFormat.currency(goal))"))
                            .font(.appCallout)
                            .foregroundStyle(Color.heroTextMuted)
                    }
                }
                Spacer(minLength: 8)
                if goal > 0 {
                    goalRing
                        .accessibilityLabel(String(localized: "home.goal.percent \(Int(percent.rounded()))"))
                }
            }
            .padding(.top, 8)

            HStack {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { index, label in
                    let filled = index < elapsedDays
                    VStack(spacing: 6) {
                        Text(label)
                            .font(.appCaption)
                            .foregroundStyle(Color.heroText.opacity(filled ? 1 : 0.55))
                        Circle()
                            .fill(Color.heroText.opacity(filled ? 1 : 0.28))
                            .frame(width: 7, height: 7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)

            HStack(alignment: .top) {
                heroStat(measurementSystem == .kilometers ? "home.stat.perKilometer" : "home.stat.rpm", rpmText)
                Spacer()
                heroStat(measurementSystem == .kilometers ? "home.stat.kilometers" : "home.stat.miles", milesText)
                Spacer()
                heroStat("home.stat.loads", "\(loadCount)")
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroGradient())
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(Color.heroText.opacity(0.28), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(1, max(0, percent / 100)))
                .stroke(Color.heroText, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(percent.rounded()))%")
                    .font(widgetNumber)
                    .foregroundStyle(Color.heroText)
                Text("home.goal.caption")
                    .font(.appCaption)
                    .foregroundStyle(Color.heroText.opacity(0.85))
            }
        }
        .frame(width: 92, height: 92)
    }

    private var widgetNumber: Font { Font(AppFont.uiFont(.bold, size: 16)) }

    private func heroStat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.appCaption)
                .foregroundStyle(Color.heroTextMuted)
            Text(value)
                .font(.appBodyMedium)
                .foregroundStyle(Color.heroText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Journal row from Android `LoadCardOptionC`: dark date band, amount, route, facts.
struct JournalLoadCard: View {
    let load: Load
    var thresholds: RPMThresholds = .default
    var onCamera: () -> Void
    var onScan: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.locale) private var locale

    private var system: MeasurementSystem { appState.settings.measurementSystem }

    private var band: RPMBand {
        RPMCalculator.band(for: load.ratePerMile, thresholds: thresholds)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 10) {
                if load.isActiveDispute {
                    Text("load.dispute")
                        .font(.appCaptionMedium)
                        .foregroundStyle(Color.forestError)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.dangerContainer, in: Capsule())
                }
                HStack(alignment: .top) {
                    Text(USMoneyFormat.currency(load.totalRate))
                        .font(.appNumberLarge)
                        .foregroundStyle(Color.forestText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        iconButton("camera", label: "load.card.camera", action: onCamera)
                        iconButton("doc.viewfinder", label: "load.card.scanner", action: onScan)
                    }
                }
                route
                facts
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.forestCard)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(headerText)
                .font(.appCaptionMedium)
                .foregroundStyle(Color.heroText)
                .lineLimit(1)
            Spacer(minLength: 8)
            if load.totalMiles > 0 {
                Text(rpmBadge)
                    .font(.appCaptionMedium)
                    .foregroundStyle(band.tint)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.successContainer, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroGradient())
    }

    private var headerText: String {
        let date = journalDate(load.effectiveFinishDate, locale: locale)
        let trip = load.tripId.hasPrefix("#") ? load.tripId : "#\(load.tripId)"
        return "\(date) · \(trip)"
    }

    private var distanceFact: String {
        let shown = USMoneyFormat.number(MeasurementUnits.displayDistance(load.totalMiles, system: system))
        if system == .kilometers {
            return String(localized: "load.card.kilometers \(shown)")
        }
        return String(localized: "load.card.miles \(shown)")
    }

    private var rpmBadge: String {
        let shown = MeasurementUnits.displayPerDistance(load.ratePerMile, system: system)
        let amount = String(format: "%.2f", locale: Locale(identifier: "en_US"), shown)
        if system == .kilometers {
            return String(localized: "load.card.perKilometer \(amount)")
        }
        return String(localized: "load.card.rpm \(amount)")
    }

    private var route: some View {
        let origin = load.pointA?.nonEmpty ?? "—"
        let destination = load.pointB?.nonEmpty ?? "—"
        return HStack(alignment: .center, spacing: 10) {
            VStack(spacing: 2) {
                Circle()
                    .stroke(Color.forestPrimary, lineWidth: 2)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(Color.forestPrimary.opacity(0.35))
                    .frame(width: 2, height: 28)
                Circle()
                    .fill(Color.forestPrimary)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(origin)
                    .font(.appBodyMedium)
                    .foregroundStyle(Color.forestText)
                    .lineLimit(1)
                Text(destination)
                    .font(.appBodyMedium)
                    .foregroundStyle(Color.forestText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private var facts: some View {
        let stops = load.stopCount > 0 ? load.stopCount : load.puCount + load.delCount
        return HStack(spacing: 10) {
            fact("mappin", distanceFact, Color.forestPrimary)
            if stops > 0 {
                fact("flag", stopsPhrase(stops, locale: locale), Color.forestWarning)
            }
            Spacer(minLength: 4)
            sourceTag
        }
    }

    private var sourceTag: some View {
        let source = LoadSourceTag.detect(tripId: load.tripId, rawMessage: load.rawMessage)
        let title: LocalizedStringKey
        let foreground: Color
        let background: AnyShapeStyle
        switch source {
        case .relay:
            title = "load.source.relay"
            foreground = Color.forestPrimary
            background = AnyShapeStyle(Color.forestSurfaceMuted)
        case .manual:
            title = "load.source.manual"
            foreground = Color.forestSuccess
            background = AnyShapeStyle(Color.successContainer)
        case .broker:
            title = "load.source.broker"
            foreground = Color.forestWarning
            background = AnyShapeStyle(Color.warningContainer)
        }
        return Text(title)
            .font(.appCaptionMedium)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }

    private func fact(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
                .lineLimit(1)
        }
    }

    private func iconButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.forestSecondary)
                .frame(width: 40, height: 40)
                .background(Color.forestSurfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}

private func journalDate(_ date: Date, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.setLocalizedDateFormatFromTemplate("EEEMMMd")
    return formatter.string(from: date)
}

private func stopsPhrase(_ count: Int, locale: Locale) -> String {
    // French agrees on 0/1 versus the rest. English and Russian keep the existing
    // one/few/many split, so "21 stop" / "21 остановка" stay exactly as they are.
    if locale.language.languageCode?.identifier == "fr" {
        if count == 0 || count == 1 {
            return String(localized: "load.card.stops.one \(count)", locale: locale)
        }
        return String(localized: "load.card.stops.many \(count)", locale: locale)
    }
    let mod10 = count % 10
    let mod100 = count % 100
    if mod10 == 1 && mod100 != 11 {
        return String(localized: "load.card.stops.one \(count)", locale: locale)
    }
    if (2...4).contains(mod10) && !(12...14).contains(mod100) {
        return String(localized: "load.card.stops.few \(count)", locale: locale)
    }
    return String(localized: "load.card.stops.many \(count)", locale: locale)
}
