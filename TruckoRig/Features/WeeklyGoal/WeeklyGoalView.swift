import SwiftUI

/// Goal tab: how the week is going and what it takes to close the gap.
struct WeeklyGoalView: View {

    @Environment(AppState.self) private var appState

    private var loads: [Load] { appState.catalog.loads }
    @State private var viewModel = WeeklyGoalViewModel()

    private var calendar: TruckingWeek { appState.settings.truckingWeek }

    private var progress: WeeklyGoalProgress {
        viewModel.progress(loads: loads, target: appState.settings.weeklyGoal, calendar: calendar, locale: AppLocale.locale)
    }

    var body: some View {
        @Bindable var model = viewModel
        let progress = progress

        ScrollView {
            LazyVStack(spacing: Spacing.section) {
                weekSwitcher
                ringCard(progress)
                paceCard(progress)
                dayPlanCard(progress)
                breakdownCard(progress)
            }
            .padding(Spacing.standard)
        }
        .forestBackground()
        .premiumGated("premium.locked.goal")
        .navigationTitle("tab.goal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("goal.edit") {
                    viewModel.goalDraft = WeeklyGoalInput.format(appState.settings.weeklyGoal)
                    viewModel.goalError = nil
                    viewModel.isEditingGoal = true
                }
            }
        }
        .sheet(isPresented: $model.isEditingGoal) {
            GoalEditorView(
                draft: $model.goalDraft,
                errorKey: $model.goalError,
                suggestions: suggestedGoals
            ) { newGoal in
                appState.setWeeklyGoal(newGoal)
            }
        }
        // The widget reads a precomputed snapshot, not the encrypted journal. Republish the
        // current week when this screen recomputes it.
        .task(id: progress) {
            if viewModel.isCurrentWeek(in: calendar) {
                appState.publishWidgetSnapshot()
            }
        }
    }

    // MARK: - Sections

    private var weekSwitcher: some View {
        HStack {
            Button {
                viewModel.step(-1, in: calendar)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("goal.previousWeek")

            Spacer()

            VStack(spacing: 2) {
                Text(progress.weekLabel)
                    .font(.appHeadline)
                if !viewModel.isCurrentWeek(in: calendar) {
                    Button("goal.backToCurrent") { viewModel.resetToCurrentWeek() }
                        .font(.appCaption)
                }
            }

            Spacer()

            Button {
                viewModel.step(1, in: calendar)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("goal.nextWeek")
            .disabled(viewModel.isCurrentWeek(in: calendar))
        }
        .foregroundStyle(Color.forestPrimary)
    }

    private func ringCard(_ progress: WeeklyGoalProgress) -> some View {
        SoftCard {
            HStack(spacing: Spacing.section) {
                GoalProgressRing(progress: progress)
                    .frame(width: 132, height: 132)

                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(Formatters.money(progress.currentGross))
                        .font(.appNumberLarge)
                        .foregroundStyle(Color.forestText)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    if progress.targetAmount > 0 {
                        Text("goal.of \(Formatters.money(progress.targetAmount))")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    } else {
                        Text("goal.notSet")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }

                    Label(progress.paceStatus.title, systemImage: progress.paceStatus.systemImage)
                        .font(.appCaptionMedium)
                        .foregroundStyle(progress.paceStatus.tint)
                }
            }
        }
    }

    private func paceCard(_ progress: WeeklyGoalProgress) -> some View {
        SoftCard {
            SectionHeader(title: "goal.pace")
            HStack {
                StatTile(
                    title: "goal.dailyNeeded",
                    value: progress.dailyTargetNeeded > 0 ? Formatters.money(progress.dailyTargetNeeded) : "—"
                )
                StatTile(
                    title: "goal.actualDaily",
                    value: progress.actualDailyYield > 0 ? Formatters.money(progress.actualDailyYield) : "—",
                    tint: progress.paceStatus.tint
                )
                StatTile(title: "goal.daysLeft", value: "\(progress.daysRemainingInWeek)")
            }
            Text("goal.pace.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private func dayPlanCard(_ progress: WeeklyGoalProgress) -> some View {
        let rows = dayPlan(for: progress)
        return SoftCard {
            HStack {
                Text("goal.day.plan")
                    .font(.appHeadline)
                    .foregroundStyle(Color.forestText)
                Spacer()
                Text(String(localized: "goal.days.left.chip \(progress.daysRemainingInWeek)"))
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.forestPrimary)
            }
            ForEach(rows, id: \.date) { row in
                dayPlanRow(row, needed: progress.dailyTargetNeeded)
            }
        }
    }

    private func dayPlanRow(_ row: DayPlanRow, needed: Double) -> some View {
        let future = row.status == .future
        let today = row.status == .today
        let amount = future ? USMoneyFormat.currency(needed) : USMoneyFormat.currency(row.gross.dollars)
        let caption = future
            ? String(localized: "goal.day.needed")
            : String(localized: "goal.day.fact \(row.planPercent)")
        return HStack(spacing: 12) {
            dayMark(row)
            VStack(alignment: .leading, spacing: 2) {
                Text(dayName(row.date))
                    .font(.appCallout)
                    .foregroundStyle(Color.forestText)
                Text(today ? String(localized: "goal.day.today \(dayDate(row.date))") : dayDate(row.date))
                    .font(.appCaption)
                    .foregroundStyle(today ? Color.forestPrimary : Color.forestTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amount)
                    .font(.appHeadline)
                    .foregroundStyle(Color.forestText)
                Text(caption)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func dayMark(_ row: DayPlanRow) -> some View {
        let label: String
        switch row.status {
        case .today: label = String(localized: "goal.day.today.cd")
        case .pastMet: label = String(localized: "goal.day.met.cd")
        case .pastMissed: label = String(localized: "goal.day.missed.cd")
        case .future: label = String(localized: "goal.day.future.cd")
        }
        return Image(systemName: markSymbol(row.status))
            .foregroundStyle(row.status == .pastMissed ? Color.forestError : Color.forestPrimary)
            .frame(width: 28, height: 28)
            .accessibilityLabel(label)
    }

    private func markSymbol(_ status: DayPlanRow.Status) -> String {
        switch status {
        case .pastMet: return "checkmark.circle.fill"
        case .pastMissed: return "xmark.circle"
        case .today: return "circle.circle"
        case .future: return "circle"
        }
    }

    private func dayPlan(for progress: WeeklyGoalProgress) -> [DayPlanRow] {
        let calendar = appState.settings.truckingWeek
        let ref = WeekRef(weekNumber: progress.weekNumber, year: progress.year)
        guard let start = calendar.startDate(of: ref), let end = calendar.endDate(of: ref) else { return [] }
        let endExclusive = calendar.calendar.date(byAdding: .day, value: 1, to: end) ?? end
        var buckets: [Int: Int64] = [:]
        for load in loads {
            guard load.date >= start, load.date < endExclusive else { continue }
            let weekday = calendar.calendar.component(.weekday, from: load.date)
            let sqlite = (weekday - 1 + 7) % 7
            buckets[sqlite, default: 0] += MoneyCents.fromDollars(load.totalRate).cents
        }
        return WeeklyDayPlan.rows(
            weekStart: start,
            today: Date(),
            grossCentsBySqliteWeekday: buckets,
            dailyNeeded: MoneyCents.fromDollars(progress.dailyTargetNeeded),
            calendar: calendar.calendar
        )
    }

    private var suggestedGoals: [Double] {
        let calendar = appState.settings.truckingWeek
        let previous = calendar.previousWeek()
        let gross = loads
            .filter { $0.weekNumber == previous.weekNumber && $0.year == previous.year }
            .reduce(0) { $0 + $1.totalRate }
        return SuggestedWeeklyGoals.amounts(closedWeekGross: gross)
    }

    private func dayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.locale
        formatter.calendar = appState.settings.truckingWeek.calendar
        formatter.timeZone = appState.settings.truckingWeek.calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func dayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.locale
        formatter.calendar = appState.settings.truckingWeek.calendar
        formatter.timeZone = appState.settings.truckingWeek.calendar.timeZone
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "").lowercased(with: AppLocale.locale)
    }

    private func breakdownCard(_ progress: WeeklyGoalProgress) -> some View {
        SoftCard {
            SectionHeader(title: "goal.week")
            HStack {
                StatTile(title: "stat.loads", value: "\(progress.loadsCount)")
                StatTile(
                    title: appState.settings.measurementSystem == .kilometers ? "stat.kilometers" : "stat.miles",
                    value: Formatters.miles(progress.totalMiles, system: appState.settings.measurementSystem)
                )
                StatTile(title: "stat.daysActive", value: progress.totalActiveDays.formatted(.number.precision(.fractionLength(1)).locale(AppLocale.locale)))
            }
            HStack {
                StatTile(title: "goal.remaining", value: Formatters.money(progress.remainingAmount))
                StatTile(title: "goal.expectedByNow", value: Formatters.money(progress.expectedGrossByNow))
            }
        }
    }
}

/// Progress ring with a marker showing where an even pace would be.
struct GoalProgressRing: View {
    let progress: WeeklyGoalProgress
    @Environment(\.cabinReduceMotion) private var reduceMotion

    private var expectedFraction: Double {
        guard progress.targetAmount > 0 else { return 0 }
        return min(1, progress.expectedGrossByNow / progress.targetAmount)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.forestSurfaceMuted, lineWidth: 14)

            Circle()
                .trim(from: 0, to: progress.progressFraction)
                .stroke(progress.paceStatus.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: progress.progressFraction)

            Circle()
                .trim(from: max(0, expectedFraction - 0.004), to: min(1, expectedFraction + 0.004))
                .stroke(Color.forestTextSecondary, style: StrokeStyle(lineWidth: 18, lineCap: .butt))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text(Formatters.percent(progress.progressFraction))
                    .font(.appNumber)
                Text("goal.complete")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("goal.a11y.progress \(Formatters.percent(progress.progressFraction))")
    }
}

/// Sheet for setting the weekly gross target, including Android's suggestion chips.
struct GoalEditorView: View {
    @Binding var draft: String
    @Binding var errorKey: String?
    var suggestions: [Double]
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent = .medium
    @FocusState private var focus: String?

    private var focusBinding: Binding<String?> {
        Binding(get: { focus }, set: { focus = $0 })
    }

    var body: some View {
        NavigationStack {
            FocusedForm(focus: $focus) {
                SoftTextField(title: "goal.target", text: $draft, keyboard: .decimalPad)
                    .keyboardFocus(KeyboardField.goalTarget, in: focusBinding)
                Text("goal.target.hint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                if !suggestions.isEmpty {
                    Text("goal.pick")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    HStack {
                        ForEach(suggestions.prefix(3), id: \.self) { amount in
                            Button(SuggestedWeeklyGoals.chip(amount)) {
                                draft = WeeklyGoalInput.format(amount)
                                errorKey = nil
                            }
                            .buttonStyle(.softSecondary)
                        }
                    }
                }
                if errorKey != nil {
                    Text("goal.error.amount")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
            }
            .navigationTitle("goal.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .onChange(of: draft) { _, newValue in
                let sanitized = WeeklyGoalInput.sanitize(newValue)
                if sanitized != newValue {
                    draft = sanitized
                }
                errorKey = nil
            }
            .onChange(of: focus) { _, newValue in
                detent = KeyboardSheetDetent.resolved(resting: .medium, fieldFocused: newValue != nil)
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
    }

    private func save() {
        guard let amount = WeeklyGoalInput.parseGoalAmount(draft) else {
            errorKey = "goal.error.amount"
            return
        }
        onSave(amount)
        dismiss()
    }
}
