import SwiftUI
import UIKit

/// What to add, improve, keep, or fix. The message leaves the phone only if the driver sends the mail.
struct ImprovementFeedbackView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var topic: ImprovementFeedbackMail.Topic = .improve
    @State private var message = ""
    @State private var submitted = false
    @State private var notice: String?

    var body: some View {
        List {
            if submitted {
                Section {
                    Text("improve.thankYou")
                        .font(.appHeadline)
                    Text("improve.thankYouBody")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    if let notice {
                        Text(notice)
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                    Button("improve.close") { dismiss() }
                }
                .listRowBackground(Color.forestCard)
            } else {
                Section {
                    Text("improve.intro")
                        .font(.appBody)
                    Text("improve.to \(ImprovementFeedbackMail.supportEmail)")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                .listRowBackground(Color.forestCard)

                Section("improve.topic") {
                    Picker("improve.topic", selection: $topic) {
                        Text("improve.topic.add").tag(ImprovementFeedbackMail.Topic.add)
                        Text("improve.topic.improve").tag(ImprovementFeedbackMail.Topic.improve)
                        Text("improve.topic.works").tag(ImprovementFeedbackMail.Topic.works)
                        Text("improve.topic.broken").tag(ImprovementFeedbackMail.Topic.broken)
                    }
                    .pickerStyle(.segmented)
                    SoftTextField(
                        title: "improve.message",
                        text: $message,
                        placeholder: "improve.message.hint"
                    )
                    SoftButton(title: "improve.send") { send() }
                    if let notice {
                        Text(notice)
                            .font(.appCaption)
                            .foregroundStyle(Color.forestError)
                    }
                }
                .listRowBackground(Color.forestCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle("improve.title")
    }

    private func send() {
        let label = topicLabel(topic)
        guard let draft = ImprovementFeedbackMail.compose(
            topic: topic,
            message: message,
            topicLabel: label,
            appVersion: Self.appVersion,
            systemName: "iOS",
            systemRelease: UIDevice.current.systemVersion
        ) else {
            notice = String(localized: "improve.empty")
            return
        }
        UIPasteboard.general.string = draft.body
        let uri = ImprovementFeedbackMail.mailtoURI(draft)
        guard let url = URL(string: uri) else {
            notice = String(localized: "improve.copied \(ImprovementFeedbackMail.supportEmail)")
            submitted = true
            return
        }
        openURL(url) { accepted in
            notice = accepted
                ? String(localized: "improve.opened")
                : String(localized: "improve.copied \(ImprovementFeedbackMail.supportEmail)")
            submitted = true
        }
    }

    private func topicLabel(_ topic: ImprovementFeedbackMail.Topic) -> String {
        switch topic {
        case .add: return String(localized: "improve.topic.add")
        case .improve: return String(localized: "improve.topic.improve")
        case .works: return String(localized: "improve.topic.works")
        case .broken: return String(localized: "improve.topic.broken")
        }
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
