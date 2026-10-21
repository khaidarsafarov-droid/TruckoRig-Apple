import SwiftUI

/// Where the journal lives. There is no account, no analytics and no server.
struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Label("privacy.badge", systemImage: "iphone")
                    .font(.appHeadline)
                    .foregroundStyle(Color.forestPrimary)
                Text("privacy.loads.title")
                    .font(.appBodyMedium)
                Text("privacy.loads.body")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            .listRowBackground(Color.forestCard)

            Section("privacy.notCollected") {
                Text("privacy.notCollected.body")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            .listRowBackground(Color.forestCard)
        }
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle("screen.privacy")
    }
}
