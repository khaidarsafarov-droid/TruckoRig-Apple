import PhotosUI
import SwiftUI
import UIKit

/// Driver and truck details, plus the way into every secondary screen.
struct ProfileView: View {

    @Environment(AppState.self) private var appState

    @State private var isEditing = false

    private var profile: DriverProfile? { appState.catalog.profile }

    private var roleTitle: String {
        switch profile?.role {
        case DriverRole.ownerOperator.rawValue: return String(localized: "onboard.role.owner")
        case DriverRole.hiredDriver.rawValue: return String(localized: "onboard.role.hired")
        case DriverRole.dispatcher.rawValue: return String(localized: "onboard.role.dispatcher")
        default: return "—"
        }
    }

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
                LabeledContent("profile.role", value: roleTitle)
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
                .overlay {
                    if let name = profile?.avatarFileName,
                       let image = MediaStore(scope: appState.persistence.scope).loadImage(named: name, kind: .photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipShape(Circle())

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

    @State private var name: String
    @State private var carrier: String
    @State private var truckModel: String
    @State private var truckYearText: String
    @State private var licensePlate: String
    @State private var homeState: String
    @State private var role: DriverRole
    @State private var cdlNumber: String
    @State private var experienceText: String
    @State private var phoneNumber: String
    @State private var telegramUsername: String
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?

    init(profile: DriverProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _carrier = State(initialValue: profile?.carrier ?? "")
        _truckModel = State(initialValue: profile?.truckModel ?? "")
        _truckYearText = State(initialValue: profile?.truckYear.map(String.init) ?? "")
        _licensePlate = State(initialValue: profile?.licensePlate ?? "")
        _homeState = State(initialValue: profile?.homeState ?? "")
        _role = State(initialValue: DriverRole(rawValue: profile?.role ?? "") ?? .ownerOperator)
        _cdlNumber = State(initialValue: profile?.cdlNumber ?? "")
        _experienceText = State(initialValue: profile?.experienceYears.map(String.init) ?? "")
        _phoneNumber = State(initialValue: profile?.phoneNumber ?? "")
        _telegramUsername = State(initialValue: profile?.telegramUsername ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("profile.driver") {
                    SoftTextField(title: "profile.name", text: $name, autocapitalization: .words)
                    Picker("profile.role", selection: $role) {
                        ForEach(DriverRole.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    SoftTextField(title: "profile.carrier", text: $carrier, autocapitalization: .words)
                    SoftTextField(title: "profile.cdl", text: $cdlNumber, autocapitalization: .characters)
                    SoftTextField(title: "profile.experience", text: $experienceText, keyboard: .numberPad)
                    SoftTextField(title: "profile.phone", text: $phoneNumber, keyboard: .phonePad)
                    SoftTextField(title: "profile.telegram", text: $telegramUsername)
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Label("profile.avatar", systemImage: "person.crop.circle")
                    }
                    .onChange(of: avatarItem) { _, item in
                        Task { await loadAvatar(item) }
                    }
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

        target.name = name.nonEmpty
        target.role = role.rawValue
        target.carrier = carrier.nonEmpty
        target.truckModel = truckModel.nonEmpty
        target.truckYear = Int(truckYearText.filter(\.isNumber))
        target.licensePlate = licensePlate.nonEmpty
        target.homeState = homeState.nonEmpty.map(USStates.normalize)
        target.cdlNumber = cdlNumber.nonEmpty
        target.experienceYears = Int(experienceText.filter(\.isNumber))
        target.phoneNumber = phoneNumber.nonEmpty
        target.telegramUsername = telegramUsername.nonEmpty
        if let avatarImage {
            let store = MediaStore(scope: appState.persistence.scope)
            if let fileName = try? store.saveJPEG(avatarImage) {
                target.avatarFileName = fileName
            }
        }
        target.weeklyGoal = appState.settings.weeklyGoal

        appState.saveProfile(target)
        dismiss()
    }

    private func loadAvatar(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            return
        }
        avatarImage = image
    }
}
