import SwiftUI

/// Driver name and truck details, plus the way into every secondary screen.
struct ProfileView: View {

    @Environment(AppState.self) private var appState

    @State private var isEditing = false

    private var profile: DriverProfile? { appState.catalog.profile }

    private var displayName: String {
        profile?.name?.nonEmpty ?? String(localized: "auth.localDriver")
    }

    var body: some View {
        List {
            Section {
                headerRow
            }
            .listRowBackground(Color.forestCard)

            Section("profile.truck") {
                LabeledContent("profile.truckModel", value: profile?.truckDescription.nonEmpty ?? "—")
                LabeledContent("profile.licensePlate", value: profile?.licensePlate?.nonEmpty ?? "—")
                LabeledContent("profile.homeState", value: profile?.homeState?.nonEmpty ?? "—")
            }
            .listRowBackground(Color.forestCard)

            Section("profile.records") {
                NavigationLink { AnalyticsView() } label: {
                    Label("screen.analytics", systemImage: "chart.bar")
                }
                NavigationLink { PaycheckListView() } label: {
                    Label("screen.paycheck", systemImage: "dollarsign.circle")
                }
                NavigationLink { DieselListView() } label: {
                    Label("screen.diesel", systemImage: "fuelpump")
                }
                NavigationLink { MiscExpenseListView() } label: {
                    Label("screen.expenses", systemImage: "receipt")
                }
                NavigationLink { TaxTrackerView() } label: {
                    Label("screen.tax", systemImage: "percent")
                }
                NavigationLink { MaintenanceListView() } label: {
                    Label("screen.maintenance", systemImage: "wrench.and.screwdriver")
                }
                NavigationLink { GalleryView() } label: {
                    Label("screen.gallery", systemImage: "photo.on.rectangle")
                }
                NavigationLink { MapScreen() } label: {
                    Label("screen.map", systemImage: "map")
                }
            }
            .listRowBackground(Color.forestCard)

            Section {
                NavigationLink { SettingsView() } label: {
                    Label("screen.settings", systemImage: "gearshape")
                }
            }
            .listRowBackground(Color.forestCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .forestBackground()
        .navigationTitle("tab.profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("action.edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            ProfileEditorView(profile: profile)
        }
    }

    private var headerRow: some View {
        HStack(spacing: Spacing.standard) {
            Text(displayName.initials.nonEmpty ?? "TR")
                .font(.appTitle)
                .foregroundStyle(Color.forestOnPrimary)
                .frame(width: 60, height: 60)
                .background(Color.forestPrimary, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.appHeadline)
                Text("profile.provider.local")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Edits the single profile row for this account.
struct ProfileEditorView: View {

    let profile: DriverProfile?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var givenName: String
    @State private var familyName: String
    @State private var truckModel: String
    @State private var truckYearText: String
    @State private var licensePlate: String
    @State private var homeState: String

    init(profile: DriverProfile?) {
        self.profile = profile
        let parts = profile?.givenAndFamilyName ?? ("", "")
        _givenName = State(initialValue: parts.given)
        _familyName = State(initialValue: parts.family)
        _truckModel = State(initialValue: profile?.truckModel ?? "")
        _truckYearText = State(initialValue: profile?.truckYear.map(String.init) ?? "")
        _licensePlate = State(initialValue: profile?.licensePlate ?? "")
        _homeState = State(initialValue: profile?.homeState ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("profile.driver") {
                    SoftTextField(title: "onboard.givenName", text: $givenName, autocapitalization: .words)
                    SoftTextField(title: "onboard.familyName", text: $familyName, autocapitalization: .words)
                }
                Section("profile.truck") {
                    SoftTextField(title: "profile.truckModel", text: $truckModel, autocapitalization: .words)
                    SoftTextField(title: "profile.truckYear", text: $truckYearText, keyboard: .numberPad)
                    SoftTextField(title: "profile.licensePlate", text: $licensePlate, autocapitalization: .characters)
                    SoftTextField(title: "profile.homeState", text: $homeState, autocapitalization: .characters)
                }
            }
            .navigationTitle("profile.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let target = profile ?? DriverProfile(
            preferredLanguage: appState.settings.language,
            weeklyGoal: appState.settings.weeklyGoal
        )

        target.name = DriverProfile.fullName(given: givenName, family: familyName)
        target.truckModel = truckModel.nonEmpty
        target.truckYear = Int(truckYearText.filter(\.isNumber))
        target.licensePlate = licensePlate.nonEmpty
        target.homeState = homeState.nonEmpty.map(USStates.normalize)
        target.weeklyGoal = appState.settings.weeklyGoal

        appState.saveProfile(target)
        dismiss()
    }
}
