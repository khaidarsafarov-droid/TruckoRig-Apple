import SwiftUI

/// Date, device and platform labels for the iCloud copy. Missing fields stay blank-safe.
enum ICloudCopyPresentation {
    static func dateText(_ exportedAt: Int64, locale: Locale = AppLocale.locale) -> String {
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
        if icloud.mediaEnabled {
            Text("settings.icloud.media.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Text("settings.icloud.media.kept")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        } else {
            Text("settings.icloud.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
        Toggle(
            "settings.icloud.auto",
            isOn: Binding(
                get: { icloud.autoSyncEnabled },
                set: { icloud.setAutoSync($0) }
            )
        )
        .tint(Color.forestPrimary)
        Toggle(
            "settings.icloud.media",
            isOn: Binding(
                get: { icloud.mediaEnabled },
                set: { icloud.setMediaEnabled($0) }
            )
        )
        .tint(Color.forestPrimary)
        Toggle(
            "settings.icloud.wifi",
            isOn: Binding(
                get: { icloud.wifiOnly },
                set: { icloud.setWifiOnly($0) }
            )
        )
        .tint(Color.forestPrimary)
        if icloud.mediaEnabled {
            Text("settings.icloud.media.power")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
        if icloud.displayedMediaBytes > 0 {
            Text(String(localized: "settings.icloud.media.size \(Self.byteText(icloud.displayedMediaBytes))"))
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
                .monospacedDigit()
        }
        if icloud.lastMediaUploadAt > 0 {
            Text(String(localized: "settings.icloud.media.uploaded \(ICloudCopyPresentation.dateText(icloud.lastMediaUploadAt))"))
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        } else if icloud.mediaEnabled && icloud.displayedMediaBytes == 0 {
            Text("settings.icloud.media.none")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        }
        mediaNotice(icloud.mediaNotice)
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

    private static func byteText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    @ViewBuilder
    private func mediaNotice(_ notice: ICloudBackupController.MediaNotice) -> some View {
        switch notice {
        case .none, .saved:
            EmptyView()
        case .waitingForWifi:
            Text("settings.icloud.media.wifiWait")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        case .waitingForPower:
            EmptyView()
        case .downloading:
            Text("settings.icloud.media.downloading")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
        case .failed:
            Text("settings.icloud.failed")
                .font(.appCaption)
                .foregroundStyle(Color.forestError)
        case .unsupported:
            Text("settings.icloud.media.unsupported")
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
                if let progress = icloud.mediaProgress, progress.total > 0 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .tint(Color.forestPrimary)
                    Text(String(localized: "settings.icloud.media.progress \(progress.completed) \(progress.total)"))
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                        .monospacedDigit()
                }
                if icloud.mediaNotice == .downloading {
                    Text("settings.icloud.media.downloading")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                Button("settings.icloud.restoreAction", role: .destructive) {
                    confirm = true
                }
                .disabled(icloud.busy)
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
        Task { await performRestoreAsync() }
    }

    private func performRestoreAsync() async {
        do {
            let outcome = try await appState.icloud.restoreConfirmed()
            if outcome.media.unsupported {
                doneMessage = String(localized: "settings.icloud.media.unsupported")
            } else if outcome.media.manifestNotReady {
                doneMessage = String(localized: "settings.icloud.media.downloading")
            } else if !outcome.media.unavailable.isEmpty {
                doneMessage = String(
                    localized: "settings.icloud.media.partial \(outcome.media.unavailable.count)"
                )
            } else {
                let report = outcome.journal
                doneMessage = String(
                    localized: "settings.backup.success \(report.loads) \(report.paychecks) \(report.diesel)"
                )
            }
        } catch let error as BackupService.Failure {
            errorMessage = BackupService.userMessage(for: error)
        } catch {
            errorMessage = String(localized: "settings.icloud.failed")
        }
    }
}
