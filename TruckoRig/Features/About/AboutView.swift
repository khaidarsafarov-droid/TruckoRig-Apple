import SwiftUI

/// How the journal is meant to be used. Telegram and Google Drive are later stages, so they are not listed.
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
            guide("about.backup.title", "about.backup.body")
            guide("about.settings.title", "about.settings.body")
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
