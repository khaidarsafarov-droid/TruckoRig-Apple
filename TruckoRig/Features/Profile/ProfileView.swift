import SwiftData
import SwiftUI

/// Driver and truck details, plus the way into every secondary screen.
struct ProfileView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [DriverProfile]

    @State private var isEditing = false
    @State private var isConfirmingSignOut = false

    private var profile: DriverProfile? { profiles.first }

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
                LabeledContent("profile.carrier", value: profile?.carrier?.nonEmpty ?? "—")
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
                NavigationLink { MaintenanceListView() } label: {
                    Label("screen.maintenance", systemImage: "wrench.and.screwdriver")
                }
                NavigationLink { GalleryView() } label: {
                    Label("screen.gallery", systemImage: "photo.on.rectangle")
                }
                NavigationLink { RouteMapView() } label: {
                    Label("screen.map", systemImage: "map")
                }
            }
            .listRowBackground(Color.forestCard)

            Section {
                NavigationLink { SettingsView() } label: {
                    Label("screen.settings", systemImage: "gearshape")
                }
                Button(role: .destructive) { isConfirmingSignOut = true } label: {
                    Label("profile.signOut", systemImage: "rectangle.portrait.and.arrow.right")
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
        .confirmationDialog("profile.signOut.confirm", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("profile.signOut", role: .destructive) { appState.signOut() }
            Button("profile.signOut.erase", role: .destructive) { appState.signOut(eraseLocalData: true) }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("profile.signOut.message")
        }
    }

    private var headerRow: some View {
        HStack(spacing: Spacing.standard) {
            Text((profile?.name ?? appState.auth.session?.displayLabel ?? "").initials.nonEmpty ?? "TR")
                .font(.appTitle)
                .foregroundStyle(Color.forestOnPrimary)
                .frame(width: 60, height: 60)
                .background(Color.forestPrimary, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.name?.nonEmpty ?? appState.auth.session?.displayLabel ?? String(localized: "auth.localDriver"))
                    .font(.appHeadline)
                Text(providerLabel)
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var providerLabel: String {
        switch appState.auth.session?.provider {
        case .apple: return String(localized: "profile.provider.apple")
        case .email: return appState.auth.session?.email ?? String(localized: "profile.provider.email")
        case .local, .none: return String(localized: "profile.provider.local")
        }
    }
}

/// Edits the single profile row for this account.
struct ProfileEditorView: View {

    let profile: DriverProfile?

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var carrier: String
    @State private var truckModel: String
    @State private var truckYearText: String
    @State private var licensePlate: String
    @State private var homeState: String

    init(profile: DriverProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _carrier = State(initialValue: profile?.carrier ?? "")
        _truckModel = State(initialValue: profile?.truckModel ?? "")
        _truckYearText = State(initialValue: profile?.truckYear.map(String.init) ?? "")
        _licensePlate = State(initialValue: profile?.licensePlate ?? "")
        _homeState = State(initialValue: profile?.homeState ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("profile.driver") {
                    SoftTextField(title: "profile.name", text: $name, autocapitalization: .words)
                    SoftTextField(title: "profile.carrier", text: $carrier, autocapitalization: .words)
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
        let target = profile ?? DriverProfile()
        if profile == nil { modelContext.insert(target) }

        target.name = name.nonEmpty
        target.carrier = carrier.nonEmpty
        target.truckModel = truckModel.nonEmpty
        target.truckYear = Int(truckYearText.filter(\.isNumber))
        target.licensePlate = licensePlate.nonEmpty
        target.homeState = homeState.nonEmpty.map(USStates.normalize)
        target.weeklyGoal = appState.settings.weeklyGoal
        target.updatedAt = Date()

        appState.sync.enqueue(.profile, id: target.id, operation: .update, in: modelContext)
        try? modelContext.save()
        dismiss()
    }
}
