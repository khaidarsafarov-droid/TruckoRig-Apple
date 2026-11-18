import SwiftUI
import UIKit

/// Shown when a ТО reminder exists and notification permission was refused.
struct MaintenanceNotificationDeniedCard: View {
    var body: some View {
        SoftCard {
            Text("maintenance.notify.denied.title")
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)
            Text("maintenance.notify.denied.body")
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            Button("maintenance.notify.settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.softSecondary)
        }
    }
}

/// New mileage or date reminder. Validation matches `MaintenanceTaskDraft`.
struct MaintenanceTaskEditor: View {
    var onSave: (MaintenanceTask) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var title = ""
    @State private var start = Date()
    @State private var due = Date()
    @State private var reminderType = MaintenanceReminderType.miles
    @State private var interval = ""
    @State private var odometer = ""
    @State private var errorKey: String?

    private var system: MeasurementSystem { appState.settings.measurementSystem }

    var body: some View {
        NavigationStack {
            Form {
                SoftTextField(
                    title: "maintenance.field.title",
                    text: $title,
                    placeholder: "maintenance.field.titleHint"
                )
                DatePicker("maintenance.field.date", selection: $start, displayedComponents: .date)
                Picker("maintenance.add.task", selection: $reminderType) {
                    Text(system == .kilometers ? "maintenance.byKilometers" : "maintenance.byMiles")
                        .tag(MaintenanceReminderType.miles)
                    Text("maintenance.byDate").tag(MaintenanceReminderType.date)
                }
                .pickerStyle(.segmented)
                if reminderType == .miles {
                    SoftTextField(
                        title: system == .kilometers ? "maintenance.interval.kilometers" : "maintenance.interval",
                        text: $interval,
                        keyboard: .decimalPad
                    )
                } else {
                    DatePicker("maintenance.dueDate", selection: $due, displayedComponents: .date)
                }
                SoftTextField(
                    title: system == .kilometers ? "maintenance.odometer.current.kilometers" : "maintenance.odometer.current",
                    text: $odometer,
                    keyboard: .decimalPad
                )
                if let errorKey {
                    Text(LocalizedStringKey(errorKey))
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
            }
            .navigationTitle("maintenance.add.task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                }
            }
        }
    }

    private func save() {
        let calendar = appState.settings.truckingWeek.calendar
        let draft = MaintenanceTaskDraft(
            title: title,
            startDate: MaintenanceMileage.isoDay(start, calendar: calendar),
            reminderType: reminderType,
            intervalMiles: UnitEntry.storageDistanceText(interval, system: system),
            odometerAtStart: UnitEntry.storageDistanceText(odometer, system: system),
            dueDate: reminderType == .date ? MaintenanceMileage.isoDay(due, calendar: calendar) : ""
        )
        switch draft.validated(nowMillis: Int64(Date().timeIntervalSince1970 * 1000)) {
        case .success(let task):
            do {
                try onSave(task)
                dismiss()
            } catch {
                errorKey = "maintenance.error.save"
            }
        case .failure(let failure):
            errorKey = failure.catalogKey(system: system)
        }
    }
}

/// Completed service lines, entered by hand or filled from a receipt scan.
struct MaintenanceArchiveEditor: View {
    @State var draft: MaintenanceArchiveDraft
    var onSave: ([MaintenanceArchiveEntry]) throws -> Void
    var onScan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var serviceDate = Date()
    @State private var errorKey: String?

    var body: some View {
        NavigationStack {
            Form {
                if draft.photoPath != nil {
                    Text("maintenance.receipt.review")
                        .font(.appHeadline)
                    Text("maintenance.receipt.hint")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                Button(scanTitle) {
                    dismiss()
                    onScan()
                }
                SoftTextField(
                    title: "maintenance.shop",
                    text: $draft.serviceName,
                    placeholder: "maintenance.shop.hint"
                )
                DatePicker("maintenance.when", selection: $serviceDate, displayedComponents: .date)
                ForEach(draft.lines.indices, id: \.self) { index in
                    lineFields(index)
                }
                Button("maintenance.add.line") {
                    draft.lines.append(MaintenanceArchiveLineDraft())
                }
                Text(linesTotal(draftTotal))
                    .font(.appHeadline)
                    .foregroundStyle(Color.forestError)
                if let errorKey {
                    Text(LocalizedStringKey(errorKey))
                        .font(.appCaption)
                        .foregroundStyle(Color.forestError)
                }
            }
            .navigationTitle(archiveTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let calendar = appState.settings.truckingWeek.calendar
                serviceDate = MaintenanceMileage.parseDay(draft.serviceDate, calendar: calendar) ?? Date()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                }
            }
        }
    }

    private func lineFields(_ index: Int) -> some View {
        VStack(alignment: .leading) {
            SoftTextField(title: "maintenance.line.name", text: $draft.lines[index].description)
            SoftTextField(title: "maintenance.line.price", text: $draft.lines[index].amount, keyboard: .decimalPad)
            if draft.lines.count > 1 {
                Button("action.delete", role: .destructive) {
                    draft.lines.remove(at: index)
                }
                .font(.appCaption)
            }
        }
    }

    private var scanTitle: LocalizedStringKey {
        draft.photoPath == nil ? "maintenance.scan" : "maintenance.retake"
    }

    private var archiveTitle: LocalizedStringKey {
        draft.photoPath == nil ? "maintenance.add.archive" : "maintenance.receipt.review"
    }

    private var draftTotal: Double {
        draft.filledLines().compactMap { $0.parsedAmount() }.reduce(0, +)
    }

    private func save() {
        let calendar = appState.settings.truckingWeek.calendar
        draft.serviceDate = MaintenanceMileage.isoDay(serviceDate, calendar: calendar)
        if let failure = draft.validationError() {
            errorKey = failure.catalogKey
            return
        }
        let entries = draft.toEntries(createdAt: Int64(Date().timeIntervalSince1970 * 1000))
        do {
            try onSave(entries)
            dismiss()
        } catch {
            errorKey = "maintenance.error.save"
        }
    }
}

extension MaintenanceTaskDraft.Failure {
    func catalogKey(system: MeasurementSystem) -> String {
        switch self {
        case .emptyTitle: return "maintenance.error.title"
        case .invalidInterval:
            return system == .kilometers ? "maintenance.error.kilometers" : "maintenance.error.interval"
        case .invalidOdometer:
            return system == .kilometers ? "maintenance.error.odometer.kilometers" : "maintenance.error.odometer"
        case .invalidDueDate: return "maintenance.error.due"
        }
    }
}

extension MaintenanceArchiveDraft.Failure {
    var catalogKey: String {
        switch self {
        case .emptyLines: return "maintenance.error.lines"
        case .emptyDescription: return "maintenance.error.description"
        case .invalidAmount: return "maintenance.error.amount"
        }
    }
}

struct ReceiptViewer: View {
    var relativePath: String
    var store: MediaStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = store.receiptImage(relativePath: relativePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("maintenance.receipt.photo")
                } else {
                    Text("maintenance.error.save")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .forestBackground()
            .navigationTitle("maintenance.receipt.photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
        }
    }
}

struct ReceiptCameraSheet: View {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var captureID = 0

    var body: some View {
        NavigationStack {
            ZStack {
                if CameraPreviewController.isCameraAvailable {
                    CameraCaptureController(
                        flash: .off,
                        captureID: captureID,
                        onImage: { image in
                            onImage(image)
                            dismiss()
                        },
                        onFailure: {}
                    )
                    .ignoresSafeArea()
                } else {
                    Text("camera.unavailable")
                        .foregroundStyle(Color.forestTextSecondary)
                }
            }
            .forestBackground()
            .navigationTitle("maintenance.camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        captureID += 1
                    } label: {
                        Image(systemName: "record.circle")
                    }
                    .disabled(!CameraPreviewController.isCameraAvailable)
                }
            }
        }
    }
}

struct ReceiptLibraryPicker: UIViewControllerRepresentable {
    var onImage: (Data, UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: (Data, UIImage) -> Void
        var dismiss: DismissAction

        init(onImage: @escaping (Data, UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.originalImage] as? UIImage) ?? UIImage()
            let data = (info[.imageURL] as? URL).flatMap { try? Data(contentsOf: $0) }
                ?? image.jpegData(compressionQuality: 0.92)
                ?? Data()
            onImage(data, image)
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
