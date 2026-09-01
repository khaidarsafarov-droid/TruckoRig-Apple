import SwiftData
import SwiftUI

/// Goal tab: how the week is going and what it takes to close the gap.
struct WeeklyGoalView: View {

    @Environment(AppState.self) private var appState
    @Query(sort: \Load.date, order: .reverse) private var loads: [Load]
    @State private var viewModel = WeeklyGoalViewModel()

    private var calendar: TruckingWeek { appState.settings.truckingWeek }

    private var progress: WeeklyGoalProgress {
        viewModel.progress(loads: loads, target: appState.settings.weeklyGoal, calendar: calendar)
    }

    var body: some View {
        @Bindable var model = viewModel
        let progress = progress

        ScrollView {
            LazyVStack(spacing: Spacing.section) {
                weekSwitcher
                ringCard(progress)
                paceCard(progress)
                breakdownCard(progress)
            }
            .padding(Spacing.standard)
        }
        .forestBackground()
        .navigationTitle("tab.goal")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("goal.edit") {
                    viewModel.goalInput = appState.settings.weeklyGoal
                    viewModel.isEditingGoal = true
                }
            }
        }
        .sheet(isPresented: $model.isEditingGoal) {
            GoalEditorView(goal: $model.goalInput) { newGoal in
                appState.settings.weeklyGoal = newGoal
            }
        }
        // The widget cannot read the account's database, so publish the current week whenever
        // this screen recomputes it.
        .task(id: progress) {
            if viewModel.isCurrentWeek(in: calendar) {
                WidgetBridge.publish(progress)
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

    private func breakdownCard(_ progress: WeeklyGoalProgress) -> some View {
        SoftCard {
            SectionHeader(title: "goal.week")
            HStack {
                StatTile(title: "stat.loads", value: "\(progress.loadsCount)")
                StatTile(title: "stat.miles", value: Formatters.miles(progress.totalMiles))
                StatTile(title: "stat.daysActive", value: progress.totalActiveDays.formatted(.number.precision(.fractionLength(1))))
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
                .animation(.easeOut(duration: 0.4), value: progress.progressFraction)

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

/// Sheet for setting the weekly gross target.
struct GoalEditorView: View {
    @Binding var goal: Double
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                SoftNumberField(title: "goal.target", value: $goal)
                Text("goal.target.hint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            .navigationTitle("goal.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        onSave(max(0, goal))
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
