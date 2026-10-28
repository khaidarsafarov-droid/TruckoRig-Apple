import SwiftUI

/// Next steps until the first load is saved. Android `HomeUxMotivators`.
struct ActivationChecklistCard: View {
    var profileComplete: Bool
    var hasGoal: Bool
    var hasDiesel: Bool
    var onProfile: () -> Void
    var onAddLoad: () -> Void
    var onGoal: () -> Void
    var onDiesel: () -> Void

    private var checklist: ActivationChecklist {
        ActivationChecklist.build(
            profileComplete: profileComplete,
            hasLoad: false,
            hasWeeklyGoal: hasGoal,
            hasDiesel: hasDiesel
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text("journal.checklist.title")
                .font(.appHeadline)
            ProgressView(value: checklist.progress)
                .tint(Color.forestPrimary)
            ForEach(Array(checklist.steps.enumerated()), id: \.offset) { _, item in
                let done = item.1
                Button {
                    open(item.0)
                } label: {
                    Label(title(item.0), systemImage: done ? "checkmark.circle.fill" : "circle")
                        .font(.appBody)
                        .foregroundStyle(done ? Color.forestSuccess : Color.forestText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(done || item.0 == .account)
            }
        }
        .padding(Spacing.standard)
        .background(Color.forestCard, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
    }

    private func title(_ step: ActivationChecklist.Step) -> LocalizedStringKey {
        switch step {
        case .account: return "journal.checklist.account"
        case .profile: return "journal.checklist.profile"
        case .firstLoad: return "journal.checklist.load"
        case .weeklyGoal: return "journal.checklist.goal"
        case .firstDiesel: return "journal.checklist.diesel"
        }
    }

    private func open(_ step: ActivationChecklist.Step) {
        switch step {
        case .account: break
        case .profile: onProfile()
        case .firstLoad: onAddLoad()
        case .weeklyGoal: onGoal()
        case .firstDiesel: onDiesel()
        }
    }
}

/// Free-version prompt after seven days. Android `Day7SurveyBanner`.
struct Day7SurveyBanner: View {
    var onSubscribe: () -> Void
    var onEnough: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text("premium.survey.title")
                .font(.appHeadline)
            Text("premium.survey.body")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Button("premium.survey.subscribe", action: onSubscribe)
                .buttonStyle(.softPrimary)
            Button("premium.survey.enough", action: onEnough)
                .font(.appCaptionMedium)
                .foregroundStyle(Color.forestTextSecondary)
        }
        .padding(Spacing.standard)
        .background(Color.forestCard, in: RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
    }
}
