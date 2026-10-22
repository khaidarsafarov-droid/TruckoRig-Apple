import SwiftUI

/// Google Drive block on Settings. The file-export section above it stays the share-sheet backup.
struct DriveBackupSection: View {
    @Environment(AppState.self) private var appState
    @State private var confirmRestore = false
    @State private var confirmUnbound = false
    @State private var conflict = false

    var body: some View {
        let drive = appState.drive
        Section("settings.drive.title") {
            if let email = drive.email {
                Text("settings.drive.statusOn \(email)")
            } else {
                Text("settings.drive.statusOff")
            }
            Text(drive.email == nil ? "settings.drive.localHint" : "settings.drive.linkedHint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Text("settings.drive.desc")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            if !drive.isConfigured {
                Text("settings.drive.unavailable")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            Text("settings.drive.last \(lastSyncText(drive.lastSyncAt))")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            if let error = drive.lastError, !error.isEmpty {
                Text("settings.drive.lastError \(error)")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestError)
            }
            if drive.offline {
                Text("settings.drive.offline")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestError)
            }
            if drive.busy {
                ProgressView()
                Text("settings.drive.busy")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            if drive.isConfigured && drive.email == nil {
                Button("settings.drive.now") { Task { await drive.connect() } }
                    .disabled(drive.busy)
            } else if drive.isConfigured {
                Toggle(
                    "settings.drive.auto",
                    isOn: Binding(
                        get: { drive.autoSyncEnabled },
                        set: { drive.setAutoSync($0) }
                    )
                )
                .disabled(drive.busy)
                Text("settings.drive.autoDesc")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
                Button("settings.drive.now") { Task { await drive.backupNow() } }
                    .disabled(drive.busy)
                Button("settings.drive.restore") { Task { await beginRestore() } }
                    .disabled(drive.busy)
                Button("settings.drive.disconnect") { drive.disconnect() }
                    .disabled(drive.busy)
            }
        }
        .alert(
            "settings.drive.title",
            isPresented: Binding(
                get: { appState.drive.notice != nil },
                set: { presented in
                    if !presented { appState.drive.notice = nil }
                }
            ),
            actions: { Button("action.ok") { appState.drive.notice = nil } },
            message: { Text(appState.drive.notice ?? "") }
        )
        .alert(
            "settings.drive.restoreTitle",
            isPresented: $confirmRestore,
            actions: {
                Button("settings.drive.restore") { Task { await finishRestore(allowUnbound: false) } }
                Button("action.cancel", role: .cancel) {}
            },
            message: {
                Text(conflict ? "settings.drive.conflict" : "settings.drive.restoreBody")
            }
        )
        .alert(
            "settings.drive.restoreTitle",
            isPresented: $confirmUnbound,
            actions: {
                Button("settings.drive.unboundAction") { Task { await finishRestore(allowUnbound: true) } }
                Button("action.cancel", role: .cancel) {}
            },
            message: { Text("settings.drive.unbound") }
        )
    }

    private func lastSyncText(_ millis: Int64) -> String {
        guard millis > 0 else { return String(localized: "settings.drive.lastNever") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }

    private func beginRestore() async {
        conflict = await appState.drive.prepareRestoreWarning()
        confirmRestore = true
    }

    private func finishRestore(allowUnbound: Bool) async {
        let outcome = await appState.drive.restore(allowUnbound: allowUnbound)
        if outcome == .unbound {
            confirmUnbound = true
        }
    }
}
