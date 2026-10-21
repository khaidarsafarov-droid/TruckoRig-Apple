import SwiftUI
import UIKit

/// ТО: mileage and date reminders, completed items, and receipt history.
struct MaintenanceListView: View {

    @Environment(AppState.self) private var appState

    @State private var showsTaskEditor = false
    @State private var showsArchiveEditor = false
    @State private var showsSourcePicker = false
    @State private var showsCamera = false
    @State private var showsLibrary = false
    @State private var viewingReceipt: ReceiptPath?
    @State private var isProcessingPhoto = false
    @State private var photoFailed = false
    @State private var archiveSeed = MaintenanceArchiveDraft(serviceDate: "")

    private var week: TruckingWeek { appState.settings.truckingWeek }

    private var progress: [MaintenanceProgress] {
        let loads = mileageLoads
        return appState.catalog.maintenance
            .filter { !$0.isCompleted }
            .map { MaintenanceMileage.progress(task: $0, loads: loads, today: Date(), week: week) }
    }

    private var completed: [MaintenanceTask] {
        Array(appState.catalog.maintenance.filter(\.isCompleted).prefix(10))
    }

    private var visits: [MaintenanceVisit] {
        MaintenanceVisits.group(appState.catalog.maintenanceArchive)
    }

    private var mileageLoads: [MaintenanceMileage.LoadInput] {
        appState.catalog.loads.map { load in
            MaintenanceMileage.LoadInput(
                tripId: load.tripId,
                id: load.id.uuidString,
                miles: load.totalMiles,
                date: MaintenanceMileage.isoDay(load.date, calendar: week.calendar),
                actualFinishDate: load.actualFinishDate.map {
                    MaintenanceMileage.isoDay($0, calendar: week.calendar)
                },
                lastDeliveryAt: load.lastDeliveryAt
            )
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.section) {
                taskSection
                archiveSection
            }
            .padding(Spacing.standard)
        }
        .forestBackground()
        .navigationTitle("screen.maintenance")
        .sheet(isPresented: $showsTaskEditor) {
            MaintenanceTaskEditor { task in
                try appState.financeRepository().addTask(task)
            }
        }
        .sheet(isPresented: $showsArchiveEditor) {
            MaintenanceArchiveEditor(draft: archiveSeed) { entries in
                try appState.financeRepository().addArchive(entries)
            } onScan: {
                showsSourcePicker = true
            }
        }
        .confirmationDialog("maintenance.scan.title", isPresented: $showsSourcePicker, titleVisibility: .visible) {
            Button("maintenance.camera") { showsCamera = true }
            Button("maintenance.gallery") { showsLibrary = true }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("maintenance.scan.hint")
        }
        .sheet(isPresented: $showsCamera) {
            ReceiptCameraSheet { image in
                acceptReceipt(image: image, original: image.jpegData(compressionQuality: 0.92))
            }
        }
        .sheet(isPresented: $showsLibrary) {
            ReceiptLibraryPicker { data, image in
                acceptReceipt(image: image, original: data)
            }
        }
        .sheet(item: $viewingReceipt) { receipt in
            ReceiptViewer(relativePath: receipt.path, store: MediaStore(scope: appState.persistence.scope))
        }
        .alert("maintenance.error.save", isPresented: $photoFailed) {
            Button("action.ok") {}
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            header("maintenance.active") { showsTaskEditor = true }
            if progress.isEmpty {
                hint("maintenance.empty.tasks")
            } else {
                ForEach(progress, id: \.task.id) { item in
                    activeCard(item)
                }
            }
            if !completed.isEmpty {
                Text("maintenance.completed")
                    .font(.appHeadline)
                    .foregroundStyle(Color.forestTextSecondary)
                    .padding(.top, Spacing.tight)
                ForEach(completed) { task in
                    completedCard(task)
                }
            }
        }
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            header("maintenance.archive.section") {
                archiveSeed = MaintenanceArchiveDraft(serviceDate: todayISO)
                showsArchiveEditor = true
            }
            Text("maintenance.archive.hint")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            if isProcessingPhoto {
                ProgressView()
                Text("maintenance.ocr")
                    .font(.appCaption)
                    .foregroundStyle(Color.forestTextSecondary)
            }
            if visits.isEmpty {
                hint("maintenance.empty.archive")
            } else {
                ForEach(visits, id: \.ids) { visit in
                    visitCard(visit)
                }
            }
        }
    }

    private func header(_ title: LocalizedStringKey, add: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.appTitle)
                .foregroundStyle(Color.forestText)
            Spacer()
            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.forestPrimary)
            }
            .accessibilityLabel(title)
        }
    }

    private func hint(_ key: LocalizedStringKey) -> some View {
        SoftCard {
            Text(key)
                .font(.appBody)
                .foregroundStyle(Color.forestTextSecondary)
        }
    }

    private func activeCard(_ item: MaintenanceProgress) -> some View {
        let urgent = item.isDue && item.task.reminderType == .miles
        return SoftCard {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(urgent ? Color.forestError : Color.forestPrimary)
                Text(item.task.title)
                    .font(.appHeadline)
                    .foregroundStyle(Color.forestText)
                Spacer()
                if item.isDue {
                    Text(urgent ? LocalizedStringKey("maintenance.urgent") : LocalizedStringKey("maintenance.due"))
                        .font(.appCaptionMedium)
                        .foregroundStyle(Color.forestError)
                }
            }
            Text(serviceDate(item.task.startDate))
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            switch item.task.reminderType {
            case .miles:
                milesBody(item, urgent: urgent)
            case .date:
                dateBody(item)
            }
            HStack {
                Button("maintenance.mark.done") {
                    try? appState.financeRepository().complete(item.task)
                }
                .buttonStyle(.softSecondary)
                Spacer()
                deleteButton { try? appState.financeRepository().delete(item.task) }
            }
        }
    }

    @ViewBuilder
    private func milesBody(_ item: MaintenanceProgress, urgent: Bool) -> some View {
        let driven = USMoneyFormat.number(item.milesDrivenSinceStart)
        let remaining = USMoneyFormat.number(max(0, item.milesRemaining ?? 0))
        Text(milesProgress(driven: driven, loads: item.loadsCounted, remaining: remaining))
            .font(.appBody)
            .foregroundStyle(urgent ? Color.forestError : Color.forestText)
        if urgent {
            Text("maintenance.urgent.message")
                .font(.appCallout)
                .foregroundStyle(Color.forestError)
        }
        Text(odometerLine(item))
            .font(.appCaption)
            .foregroundStyle(Color.forestTextSecondary)
        ProgressView(value: min(1, max(0, item.progressFraction)))
            .tint(urgent ? Color.forestError : Color.forestPrimary)
    }

    private func dateBody(_ item: MaintenanceProgress) -> some View {
        Text(dateStatus(item))
            .font(.appBody)
            .foregroundStyle(item.isDue ? Color.forestError : Color.forestText)
    }

    private func completedCard(_ task: MaintenanceTask) -> some View {
        SoftCard {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.forestPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.appBody)
                        .foregroundStyle(Color.forestText)
                    Text(task.startDate)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                Spacer()
                deleteButton { try? appState.financeRepository().delete(task) }
            }
        }
    }

    private func visitCard(_ visit: MaintenanceVisit) -> some View {
        let store = MediaStore(scope: appState.persistence.scope)
        let path = visit.photoPath
        return SoftCard {
            HStack(alignment: .top, spacing: Spacing.tight) {
                if let path, let image = store.receiptImage(relativePath: path) {
                    Button {
                        viewingReceipt = ReceiptPath(path: path)
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("maintenance.receipt.photo")
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(visitTitle(visit))
                            .font(.appCallout)
                            .foregroundStyle(Color.forestText)
                        if path != nil {
                            Text("maintenance.hasReceipt")
                                .font(.appCaption)
                                .foregroundStyle(Color.forestPrimary)
                        }
                    }
                    Text(visit.serviceDate)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    if visit.lines.count > 1 || !visit.shopName.isEmpty {
                        ForEach(visit.lines) { line in
                            HStack {
                                Text(line.description.isEmpty ? String(localized: "maintenance.line.name") : line.description)
                                    .font(.appCaption)
                                    .foregroundStyle(Color.forestTextSecondary)
                                Spacer()
                                Text(USMoneyFormat.currency(line.amount.dollars, fractionDigits: 2))
                                    .font(.appCaption)
                                    .foregroundStyle(Color.forestTextSecondary)
                            }
                        }
                    }
                    Text(linesTotal(visit.total))
                        .font(.appHeadline)
                        .foregroundStyle(Color.forestError)
                }
                Spacer(minLength: 0)
                deleteButton {
                    try? appState.financeRepository().deleteVisit(
                        ids: visit.ids,
                        store: MediaStore(scope: appState.persistence.scope)
                    )
                }
            }
        }
    }

    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
                .foregroundStyle(Color.forestTextSecondary)
        }
        .accessibilityLabel("action.delete")
    }

    private var todayISO: String {
        MaintenanceMileage.isoDay(Date(), calendar: week.calendar)
    }

    private func visitTitle(_ visit: MaintenanceVisit) -> String {
        if !visit.shopName.isEmpty { return visit.shopName }
        return visit.lines.first?.description ?? ""
    }

    private func acceptReceipt(image: UIImage, original: Data?) {
        isProcessingPhoto = true
        let store = MediaStore(scope: appState.persistence.scope)
        let bytes = original ?? image.jpegData(compressionQuality: 0.92)
        guard let bytes, UIImage(data: bytes) != nil else {
            isProcessingPhoto = false
            photoFailed = true
            return
        }
        let name = "receipt_\(Int64(Date().timeIntervalSince1970 * 1000)).jpg"
        guard let path = try? store.writeReceipt(data: bytes, fileName: name),
              let saved = store.receiptImage(relativePath: path)
        else {
            isProcessingPhoto = false
            photoFailed = true
            return
        }
        Task {
            let recognition = await OCRService.recognizeText(in: saved)
            let parsed = ServiceReceiptParser.parse(recognition?.text ?? "", defaultDate: todayISO)
            archiveSeed = MaintenanceArchiveDraft(
                serviceName: parsed.serviceName ?? "",
                serviceDate: parsed.date ?? todayISO,
                lines: receiptLines(parsed),
                photoPath: path,
                ocrText: recognition?.text
            )
            isProcessingPhoto = false
            showsArchiveEditor = true
        }
    }

    private func receiptLines(_ parsed: ServiceReceiptParse) -> [MaintenanceArchiveLineDraft] {
        if !parsed.lineItems.isEmpty {
            return parsed.lineItems.map {
                MaintenanceArchiveLineDraft(
                    description: $0.description,
                    amount: MaintenanceArchiveDraft.formatAmount($0.amount)
                )
            }
        }
        return [
            MaintenanceArchiveLineDraft(
                description: parsed.descriptionHint ?? "",
                amount: MaintenanceArchiveDraft.formatAmount(parsed.amount ?? 0)
            ),
        ]
    }
}

struct ReceiptPath: Identifiable {
    var path: String
    var id: String { path }
}

private func serviceDate(_ iso: String) -> String {
    String(localized: "maintenance.serviceDate \(iso)")
}

private func milesProgress(driven: String, loads: Int, remaining: String) -> String {
    String(localized: "maintenance.miles.progress \(driven) \(loads) \(remaining)")
}

private func odometerLine(_ item: MaintenanceProgress) -> String {
    let estimated = USMoneyFormat.number(item.estimatedOdometer ?? 0)
    let target = USMoneyFormat.number(item.targetOdometer ?? 0)
    return String(localized: "maintenance.odometer.estimate \(estimated) \(target)")
}

private func dateStatus(_ item: MaintenanceProgress) -> String {
    guard let days = item.daysRemaining else { return item.task.dueDate ?? "" }
    if days < 0 { return String(localized: "maintenance.overdue \(-days)") }
    if days == 0 { return String(localized: "maintenance.due.today") }
    return String(localized: "maintenance.days.left \(days)")
}

func linesTotal(_ amount: Double) -> String {
    String(localized: "maintenance.lines.total \(USMoneyFormat.number(amount, fractionDigits: 2))")
}
