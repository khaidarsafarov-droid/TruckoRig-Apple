import SwiftUI

/// Journal spreadsheet. Android locks the same export behind Premium.
struct SettingsJournalExport: View {
    @Environment(AppState.self) private var appState
    @State private var shareFile: SharedCSV?
    @State private var showPaywall = false
    @State private var errorMessage: String?

    var body: some View {
        Button("settings.export.csv") { export() }
        .sheet(item: $shareFile) { file in
            ShareSheet(items: [file.url])
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallSheet(onClose: { showPaywall = false })
                .environment(appState)
        }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private func export() {
        guard appState.premium.isActive else {
            showPaywall = true
            return
        }
        let records = appState.catalog.loads.map { load in
            LoadCSVRecord(
                tripId: load.tripId,
                date: DateUtils.isoDay(load.date),
                pointA: load.pointA ?? "",
                pointB: load.pointB ?? "",
                totalRate: load.totalRate,
                totalMiles: load.drivenMiles,
                stopCount: load.stopCount,
                weekNumber: load.weekNumber,
                year: load.year
            )
        }
        let csv = CSVExportParser.csv(from: records)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TruckoRig-loads.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            shareFile = SharedCSV(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SharedCSV: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
