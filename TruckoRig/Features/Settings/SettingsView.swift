import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Language, week start, RPM bands and backup.
struct SettingsView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var export: ExportedBackup?
    @State private var isImporting = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var settings: AppSettings { appState.settings }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("settings.general") {
                Picker("settings.language", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
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
            }

            Section("settings.rpm") {
                SoftNumberField(title: "settings.rpm.min", value: $settings.rpmMinProfit)
                SoftNumberField(title: "settings.rpm.target", value: $settings.rpmTargetProfit)
                if let failure = settings.rpmThresholds.validationFailure {
                    Text(failure.localizedMessage)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
            }

            Section("settings.backup") {
                Button("settings.backup.export") { exportBackup() }
                Button("settings.backup.import") { isImporting = true }
                Text("settings.backup.hint")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
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
        .sheet(item: $export) { export in
            ShareSheet(items: [export.url])
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): restore(from: url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
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
            try WeekReindexer.reindex(in: modelContext, week: appState.settings.truckingWeek)
            appState.publishWidgetSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportBackup() {
        do {
            let url = try BackupService.exportSnapshot(from: modelContext, scope: appState.persistence.scope)
            export = ExportedBackup(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(from url: URL) {
        do {
            let report = try BackupService.restore(
                from: url,
                into: modelContext,
                week: appState.settings.truckingWeek
            )
        appState.adoptRestoredGoal()
            appState.publishWidgetSnapshot()
            statusMessage = String(
                localized: "settings.backup.report \(report.inserted) \(report.updated) \(report.skipped)"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
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
