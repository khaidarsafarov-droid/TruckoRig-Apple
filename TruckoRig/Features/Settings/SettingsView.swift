import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Language, week start, RPM bands and backup.
struct SettingsView: View {

    @Environment(AppState.self) private var appState

    @State private var exportDocument = BackupJSONDocument()
    @State private var exportName = "TruckoRig_Backup"
    @State private var exportLoadCount = 0
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var confirmRestore: BackupConfirm?
    @State private var pendingJSON: String?
    @State private var pendingExportedAt: Int64 = 0
    @State private var pendingUnbound = false
    @State private var pendingForeign = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var settings: AppSettings { appState.settings }

    private var quietRange: String {
        let start = String(format: "%02d:00", settings.quietStartHour)
        let end = String(format: "%02d:00", settings.quietEndHour)
        return String(localized: "settings.quiet.range \(start) \(end)")
    }

    private func quietHour(_ title: LocalizedStringKey, hour: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%02d:00", hour.wrappedValue))
                    .foregroundStyle(Color.forestPrimary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(hour.wrappedValue) },
                    set: { hour.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...23,
                step: 1
            )
        }
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("settings.appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.theme.title")
                        .font(.appBodyMedium)
                        .foregroundStyle(Color.forestText)
                    HStack(spacing: 8) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Button {
                                settings.themeMode = mode
                            } label: {
                                Text(mode.titleKey)
                                    .font(.appCaptionMedium)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                    .foregroundStyle(settings.themeMode == mode ? Color.forestOnPrimary : Color.forestText)
                                    .background(
                                        settings.themeMode == mode
                                            ? AnyShapeStyle(Color.forestPrimary)
                                            : AnyShapeStyle(Color.forestSurfaceMuted),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(settings.themeMode == mode ? .isSelected : AccessibilityTraits())
                        }
                    }
                }
                if settings.themeMode.showsOledToggle {
                    Toggle("settings.oled.title", isOn: $settings.oledDark)
                    Text("settings.oled.subtitle")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
            }

            Section("settings.general") {
                Picker("settings.language", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.units")
                        .font(.appBodyMedium)
                        .foregroundStyle(Color.forestText)
                    HStack(spacing: 8) {
                        ForEach(MeasurementSystem.allCases, id: \.self) { system in
                            Button {
                                settings.chooseMeasurementSystem(system)
                            } label: {
                                Text(system == .kilometers ? "settings.units.kilometers" : "settings.units.miles")
                                    .font(.appCaptionMedium)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                    .foregroundStyle(settings.measurementSystem == system ? Color.forestOnPrimary : Color.forestText)
                                    .background(
                                        settings.measurementSystem == system
                                            ? AnyShapeStyle(Color.forestPrimary)
                                            : AnyShapeStyle(Color.forestSurfaceMuted),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(settings.measurementSystem == system ? .isSelected : AccessibilityTraits())
                        }
                    }
                    Text("settings.units.hint")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                Picker("settings.weekStart", selection: $settings.weekStart) {
                    ForEach(WeekStartDay.allCases, id: \.self) { day in
                        Text(weekdayName(day)).tag(day)
                    }
                }
                .onChange(of: settings.weekStart) { reindexWeeks() }
                Text("settings.weekStart.hint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                Picker("settings.dieselWeekStart", selection: $settings.dieselWeekStart) {
                    ForEach(WeekStartDay.allCases, id: \.self) { day in
                        Text(weekdayName(day)).tag(day)
                    }
                }
                Text("settings.dieselWeekStart.hint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                Toggle("settings.reduceMotion", isOn: $settings.reduceMotion)
                Text("settings.reduceMotion.hint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }

            Section {
                Toggle("settings.notify.missing", isOn: $settings.notifyMissingWeek)
                Text("settings.notify.missing.subtitle")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                Toggle("settings.notify.maintenance", isOn: $settings.notifyMaintenance)
                Text("settings.notify.maintenance.subtitle")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                Toggle("settings.quiet.title", isOn: $settings.quietHoursEnabled)
                Text("settings.quiet.desc")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                if settings.quietHoursEnabled {
                    quietHour("settings.quiet.start", hour: $settings.quietStartHour)
                    quietHour("settings.quiet.end", hour: $settings.quietEndHour)
                    Text(quietRange)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                } else {
                    Text("settings.quiet.off")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
            }
            .onChange(of: settings.notifyMissingWeek) { appState.scheduleReminders() }
            .onChange(of: settings.notifyMaintenance) { appState.scheduleReminders() }
            .onChange(of: settings.quietHoursEnabled) { appState.scheduleReminders() }
            .onChange(of: settings.quietStartHour) { appState.scheduleReminders() }
            .onChange(of: settings.quietEndHour) { appState.scheduleReminders() }

            Section(settings.measurementSystem == .kilometers ? "settings.rpm.perKilometer" : "settings.rpm") {
                SoftNumberField(
                    title: "settings.rpm.min",
                    value: UnitEntry.perDistance(stored: $settings.rpmMinProfit, system: settings.measurementSystem)
                )
                SoftNumberField(
                    title: "settings.rpm.target",
                    value: UnitEntry.perDistance(stored: $settings.rpmTargetProfit, system: settings.measurementSystem)
                )
                if let failure = settings.rpmThresholds.validationFailure {
                    Text(failure.localizedMessage)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
            }

            Section("settings.backup") {
                Text("settings.backup.hint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                Button("settings.backup.export") { exportBackup() }
                SettingsJournalExport()
                Button("settings.backup.import") { confirmRestore = .replace }
                Text("settings.backup.restoreHint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }

            #if !SIDELOAD
            ICloudBackupSection()
            #endif

            TelegramSettingsSection()

            Section {
                SettingsPremiumSection()
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section("settings.more") {
                NavigationLink { PrivacyView() } label: { Label("screen.privacy", systemImage: "lock") }
                NavigationLink { AboutView() } label: { Label("screen.about", systemImage: "info.circle") }
                NavigationLink { ImprovementFeedbackView() } label: { Label("improve.title", systemImage: "envelope") }
            }

            Section("settings.about") {
                LabeledContent("settings.about.version", value: Self.appVersion)
                LabeledContent("settings.about.account", value: appState.persistence.scope.storeKey)
                if !AppFont.isBundled {
                    Text("settings.about.fontFallback")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                if let failure = appState.persistence.storeFailure {
                    Text("settings.about.storeFailure \(failure)")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
            }
        }
        .navigationTitle("screen.settings")
        .scrollContentBackground(.hidden)
        .forestBackground()
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportName
        ) { result in
            switch result {
            case .success(let url):
                statusMessage = String(
                    localized: "settings.backup.saved \(exportLoadCount) \(url.lastPathComponent)"
                )
            case .failure(let error):
                if !Self.isCancellation(error) { errorMessage = error.localizedDescription }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json, .plainText, .text, .data]
        ) { result in
            switch result {
            case .success(let url): inspectImport(url)
            case .failure(let error):
                if !Self.isCancellation(error) { errorMessage = error.localizedDescription }
            }
        }
        .alert(
            "settings.backup.restoreTitle",
            isPresented: Binding(
                get: { confirmRestore != nil },
                set: { if !$0 { confirmRestore = nil } }
            ),
            presenting: confirmRestore,
            actions: { confirm in
                switch confirm {
                case .replace:
                    Button("settings.backup.restoreAction") { isImporting = true }
                    Button("action.cancel", role: .cancel) {}
                case .unbound:
                    Button("settings.backup.unboundAction") { continueAfterUnbound() }
                    Button("action.cancel", role: .cancel) { pendingJSON = nil }
                case .foreignAccount:
                    Button("settings.backup.foreignAction") { continueAfterForeign() }
                    Button("action.cancel", role: .cancel) { pendingJSON = nil }
                case .localNewer:
                    Button("settings.backup.restoreAction") { commitPendingRestore() }
                    Button("action.cancel", role: .cancel) { pendingJSON = nil }
                }
            },
            message: { confirm in
                switch confirm {
                case .replace:
                    Text("settings.backup.restoreBody")
                case .unbound:
                    Text("settings.backup.unbound")
                case .foreignAccount:
                    Text("settings.backup.foreignAccount")
                case .localNewer:
                    Text("settings.backup.localNewer")
                }
            }
        )
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
        .alert(
            "settings.backup.done",
            isPresented: .isPresented($statusMessage),
            actions: { Button("action.ok") {} },
            message: { Text(statusMessage ?? "") }
        )
    }

    private static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func weekdayName(_ day: WeekStartDay) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = day.calendarWeekday - 1
        return symbols.indices.contains(index) ? symbols[index].capitalized : day.rawValue
    }

    /// Week numbers are cached on every load, so switching the week start has to refile them.
    private func reindexWeeks() {
        do {
            try WeekReindexer.reindex(in: appState.persistence.database, week: appState.settings.truckingWeek)
            appState.reloadJournal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportBackup() {
        do {
            let file = try BackupService.exportFile(
                from: appState.persistence.database,
                settings: appState.settings,
                identity: BackupIdentityStore.standard()
            )
            exportDocument = BackupJSONDocument(data: file.data)
            exportLoadCount = file.loadCount
            exportName = file.fileName.hasSuffix(".json") ? String(file.fileName.dropLast(5)) : file.fileName
            isExporting = true
        } catch let error as BackupService.Failure {
            errorMessage = BackupService.userMessage(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func inspectImport(_ url: URL) {
        do {
            let data = try BackupService.read(url: url)
            let preview = try BackupService.preview(data: data)
            pendingJSON = preview.json
            pendingExportedAt = preview.exportedAt
            pendingUnbound = preview.unbound
            pendingForeign = preview.accountMismatch
            if preview.unbound {
                confirmRestore = .unbound
                return
            }
            if preview.accountMismatch {
                confirmRestore = .foreignAccount
                return
            }
            if try BackupService.shouldWarnBeforeRestore(
                in: appState.persistence.database,
                backupExportedAt: preview.exportedAt
            ) {
                confirmRestore = .localNewer
                return
            }
            try commitRestore(allowUnbound: false, allowForeign: false)
        } catch let error as BackupService.Failure {
            errorMessage = BackupService.userMessage(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func continueAfterForeign() {
        do {
            if try BackupService.shouldWarnBeforeRestore(
                in: appState.persistence.database,
                backupExportedAt: pendingExportedAt
            ) {
                confirmRestore = .localNewer
                return
            }
            try commitRestore(allowUnbound: false, allowForeign: true)
        } catch let error as BackupService.Failure {
            errorMessage = BackupService.userMessage(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func continueAfterUnbound() {
        do {
            if try BackupService.shouldWarnBeforeRestore(
                in: appState.persistence.database,
                backupExportedAt: pendingExportedAt
            ) {
                confirmRestore = .localNewer
                return
            }
            try commitRestore(allowUnbound: true, allowForeign: pendingForeign)
        } catch let error as BackupService.Failure {
            errorMessage = BackupService.userMessage(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitPendingRestore() {
        do {
            try commitRestore(allowUnbound: pendingUnbound, allowForeign: pendingForeign)
        } catch let error as BackupService.Failure {
            errorMessage = BackupService.userMessage(for: error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitRestore(allowUnbound: Bool, allowForeign: Bool) throws {
        guard let json = pendingJSON else { return }
        let report = try BackupService.restoreBackupJSON(
            json,
            into: appState.persistence.database,
            settings: appState.settings,
            identity: BackupIdentityStore.standard(),
            media: MediaStore(scope: appState.persistence.scope),
            allowUnboundAccount: allowUnbound,
            allowForeignAccount: allowForeign
        )
        pendingJSON = nil
        pendingUnbound = false
        pendingForeign = false
        appState.reloadJournal()
        statusMessage = String(
            localized: "settings.backup.success \(report.loads) \(report.paychecks) \(report.diesel)"
        )
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
    }
}

/// Which restore confirmation is on screen.
private enum BackupConfirm: Identifiable {
    case replace
    case unbound
    case foreignAccount
    case localNewer

    var id: Self { self }
}

/// JSON document handed to the Files exporter. The suggested name supplies the `.json` extension.
struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Backup file waiting to be shared.
struct ExportedBackup: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// `UIActivityViewController` for sharing the exported backup.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
