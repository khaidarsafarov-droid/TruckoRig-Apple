import SwiftUI

/// Date, device and platform labels for the iCloud copy. Missing fields stay blank-safe.
enum ICloudCopyPresentation {
    static func dateText(_ exportedAt: Int64, locale: Locale = .current) -> String {
        guard exportedAt > 0 else { return String(localized: "settings.icloud.unknown") }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: Double(exportedAt) / 1000))
    }

    static func deviceName(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return String(localized: "settings.icloud.unknown") }
        return String(trimmed.prefix(80))
    }

    static func platformName(_ raw: String?) -> String {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case ICloudBackupPolicy.originPlatformIOS:
            return String(localized: "settings.icloud.platform.ios")
        case ICloudBackupPolicy.originPlatformAndroid:
            return String(localized: "settings.icloud.platform.android")
        default:
            return String(localized: "settings.icloud.unknown")
        }
    }
}

/// iCloud Drive status on Settings. File export below this section keeps working when iCloud is off.
struct ICloudBackupSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let icloud = appState.icloud
        Section("settings.icloud.section") {
            switch icloud.availability {
            case .unknown:
                Text("settings.icloud.checking")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            case .signedOut:
                Text("settings.icloud.unavailable")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            case .containerMissing:
                Text("settings.icloud.container")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            case .available:
                available(icloud)
            }
        }
    }

    @ViewBuilder
    private func available(_ icloud: ICloudBackupController) -> some View {
        Text("settings.icloud.hint")
            .font(.appCaption)
            .foregroundStyle(Color.forestTextSecondary)
        Toggle(
            "settings.icloud.auto",
            isOn: Binding(
                get: { icloud.autoSyncEnabled },
                set: { icloud.setAutoSync($0) }
            )
        )
        if icloud.lastSyncAt > 0 {
            Text(String(localized: "settings.icloud.lastSync \(ICloudCopyPresentation.dateText(icloud.lastSyncAt))"))
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
        if icloud.remoteIsNewer() {
            Text("settings.icloud.newerRemote")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
        notice(icloud.notice)
        Button("settings.icloud.sync") {
            Task { await icloud.syncNow() }
        }
        .disabled(icloud.busy)
        if icloud.remote != nil {
            NavigationLink("settings.icloud.restore") {
                ICloudRestoreView()
            }
        } else if icloud.notice != .downloading && icloud.notice != .schemaTooNew {
            Text("settings.icloud.empty")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    @ViewBuilder
    private func notice(_ notice: ICloudBackupController.Notice) -> some View {
        switch notice {
        case .none:
            EmptyView()
        case .saved:
            Text("settings.icloud.saved")
                .font(.appCaption)
                .foregroundStyle(Color.forestPrimary)
        case .failed:
            Text("settings.icloud.failed")
                .font(.appCaption)
                .foregroundStyle(Color.forestError)
        case .downloading:
            Text("settings.icloud.downloading")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        case .schemaTooNew:
            Text("settings.backup.schema")
                .font(.appCaption)
                .foregroundStyle(Color.forestError)
        }
    }
}

/// Shows the iCloud copy, then asks before replacing the journal.
struct ICloudRestoreView: View {
    @Environment(AppState.self) private var appState
    @State private var confirm = false
    @State private var errorMessage: String?
    @State private var doneMessage: String?

    var body: some View {
        let icloud = appState.icloud
        Form {
            if let remote = icloud.remote {
                LabeledContent(
                    "settings.icloud.date",
                    value: ICloudCopyPresentation.dateText(remote.exportedAt)
                )
                LabeledContent(
                    "settings.icloud.device",
                    value: ICloudCopyPresentation.deviceName(remote.originDevice)
                )
                LabeledContent(
                    "settings.icloud.platform",
                    value: ICloudCopyPresentation.platformName(remote.originPlatform)
                )
                if icloud.copyIsOlderThanLocal() {
                    Text("settings.backup.localNewer")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
                if remote.accountMismatch {
                    Text("settings.backup.foreignAccount")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
                if remote.unbound {
                    Text("settings.backup.unbound")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                Button("settings.icloud.restoreAction", role: .destructive) {
                    confirm = true
                }
            } else {
                Text("settings.icloud.empty")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
        }
        .navigationTitle("settings.icloud.restore")
        .scrollContentBackground(.hidden)
        .forestBackground()
        .task { await appState.icloud.reloadRemote() }
        .confirmationDialog(
            "settings.icloud.restoreTitle",
            isPresented: $confirm,
            titleVisibility: .visible
        ) {
            Button("settings.icloud.restoreAction", role: .destructive) { performRestore() }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("settings.backup.restoreBody")
        }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
        .alert(
            "settings.backup.done",
            isPresented: .isPresented($doneMessage),
            actions: { Button("action.ok") {} },
            message: { Text(doneMessage ?? "") }
        )
    }

    private func performRestore() {
        do {
            let report = try appState.icloud.restore(confirmed: true)
            doneMessage = String(
                localized: "settings.backup.success \(report.loads) \(report.paychecks) \(report.diesel)"
            )
        } catch let error as BackupService.Failure {
            errorMessage = BackupService.userMessage(for: error)
        } catch {
            errorMessage = String(localized: "settings.icloud.failed")
        }
    }
}
