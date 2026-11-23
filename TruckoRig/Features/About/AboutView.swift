import SwiftUI

/// How the journal is meant to be used. The numbered sections follow the Android guide.
struct AboutView: View {

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("about.version", value: version)
                SupportContactRow()
                Text("about.intro")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            .listRowBackground(Color.forestCard)

            guide("about.loads.title", "about.loads.body")
            guide("about.home.title", "about.home.body")
            guide("about.dispute.title", "about.dispute.body")
            guide("about.goal.title", "about.goal.body")
            guide("about.diesel.title", "about.diesel.body")
            guide("about.paycheck.title", "about.paycheck.body")
            guide("about.tax.title", "about.tax.body")
            guide("about.reports.title", "about.reports.body")
            guide("about.map.title", "about.map.body")
            guide("about.docs.title", "about.docs.body")
            guide("about.maintenance.title", "about.maintenance.body")
            guide("about.widget.title", "about.widget.body")
            guide("about.telegram.title", "about.telegram.body")
            guide("about.backup.title", "about.backup.body")
            guide("about.settings.title", "about.settings.body")

            Section {
                NavigationLink {
                    LicenseNoticesView()
                } label: {
                    Text("about.licenses")
                }
            }
            .listRowBackground(Color.forestCard)
        }
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle("screen.about")
    }

    private func guide(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        Section {
            Text(body)
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        } header: {
            Text(title)
        }
        .listRowBackground(Color.forestCard)
    }
}

/// DM Sans, Roboto, GRDB, SQLCipher, and the Maps terms, read from the app bundle.
struct LicenseNoticesView: View {
    private var notice: String {
        let names = ["NOTICE", "DMSans-OFL", "Roboto-LICENSE"]
        let parts = names.compactMap { name -> String? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return text
        }
        if parts.count == names.count {
            return parts.joined(separator: "\n\n")
        }
        return String(localized: "about.licenses.missing")
    }

    var body: some View {
        ScrollView {
            Text(notice)
                .font(.body)
                .foregroundStyle(Color.forestText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(Spacing.standard)
        }
        .forestBackground()
        .navigationTitle("about.licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The one support address, opened in the system mail app.
struct SupportContactRow: View {
    var body: some View {
        LabeledContent("about.support") {
            Link(
                ImprovementFeedbackMail.supportEmail,
                destination: URL(string: "mailto:\(ImprovementFeedbackMail.supportEmail)")!
            )
        }
    }
}
