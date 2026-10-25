import SwiftUI
import UIKit

/// Geotagged camera. A load (journal card, load screen, or the widget picker) is saved on each
/// shot. A free session only watermarks the latest Trip ID and writes the rows when the driver
/// saves the batch — the same split as Android `CameraViewModel`.
struct CameraView: View {

    var load: Load? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var locationProvider = LocationProvider()
    @State private var attach = CameraAttachContext.fromLatestLoad(loadId: nil, tripId: nil, loadDate: nil)
    @State private var photos: [SessionPhoto] = []
    @State private var isProcessing = false
    @State private var reviewing = false
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @State private var flash = CameraFlashMode.off
    @State private var captureID = 0
    @State private var showLibrary = false
    @State private var shareItems: [Any] = []
    @State private var isSharing = false

    private var cameraAvailable: Bool { CameraPreviewController.isCameraAvailable }

    var body: some View {
        Group {
            if reviewing {
                ScrollView {
                    PhotoBatchReviewView(
                        photos: photos,
                        isSaving: isProcessing,
                        onAddMore: { reviewing = false },
                        onRemove: removePhoto,
                        onSaveAll: { Task { await persistAll(thenShare: false) } },
                        onShare: { Task { await persistAll(thenShare: true) } }
                    )
                    .padding(Spacing.standard)
                }
                .forestBackground()
            } else if cameraAvailable {
                liveCamera
            } else {
                unavailable
            }
        }
        .navigationTitle("camera.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel") { requestLeave() }
            }
            if cameraAvailable && !reviewing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("camera.openLibrary") { showLibrary = true }
                }
            }
            if !photos.isEmpty && !reviewing {
                ToolbarItem(placement: .principal) {
                    Button("camera.finishBatch \(photos.count)") { reviewing = true }
                }
            }
        }
        .task { prepare() }
        .sheet(isPresented: $showLibrary) {
            ImagePicker(sourceType: .photoLibrary) { image in
                Task { await process(image) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isSharing) {
            ActivityShare(items: shareItems)
        }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
        .confirmationDialog(
            "camera.discardTitle",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("camera.discardConfirm", role: .destructive) { discard(removeAttached: true) }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("camera.discardMessage")
        }
        .overlay {
            if isProcessing && !reviewing {
                ProgressView("camera.processing")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var liveCamera: some View {
        ZStack {
            CameraCaptureController(flash: flash, captureID: captureID) { image in
                Task { await process(image) }
            } onFailure: {
                errorMessage = String(localized: "camera.captureFailed")
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        flash = flash.next
                    } label: {
                        Image(systemName: flashSymbol)
                            .font(.title3)
                            .foregroundStyle(Color.heroText)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.45), in: Circle())
                    }
                    .accessibilityLabel(flashLabel)
                    Spacer()
                    if !photos.isEmpty {
                        Button { reviewing = true } label: {
                            Text("camera.batchCount \(photos.count)")
                                .font(.appCaptionMedium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.softPrimary)
                    }
                }
                .padding(Spacing.standard)
                if !locationProvider.isAuthorized {
                    Text("camera.noGps")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.forestCard.faded(to: 0.9), in: Capsule())
                }
                Spacer()
                Button {
                    guard !isProcessing else { return }
                    captureID += 1
                } label: {
                    Circle()
                        .strokeBorder(Color.brandGold, lineWidth: 4)
                        .background(Circle().fill(Color.heroText))
                        .frame(width: 76, height: 76)
                }
                .disabled(isProcessing)
                .padding(.bottom, 28)
                .accessibilityLabel("camera.title")
            }
        }
    }

    private var unavailable: some View {
        EmptyStateView(
            systemImage: "camera",
            title: "camera.unavailable",
            message: "camera.unavailableMessage",
            actionTitle: "camera.openLibrary",
            action: { showLibrary = true }
        )
        .padding(Spacing.standard)
        .frame(maxHeight: .infinity, alignment: .center)
        .forestBackground()
    }

    private var flashSymbol: String {
        switch flash {
        case .off: return "bolt.slash"
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        }
    }

    private var flashLabel: String {
        switch flash {
        case .off: return String(localized: "camera.flash.off")
        case .auto: return String(localized: "camera.flash.auto")
        case .on: return String(localized: "camera.flash.on")
        }
    }

    private func prepare() {
        locationProvider.requestAuthorization()
        if let explicit = CameraAttachContext.fromExplicit(
            attachLoadId: load?.id.uuidString,
            attachTripId: load?.tripId,
            attachLoadDate: load?.attachmentDateISO()
        ) {
            attach = explicit
            return
        }
        let latest = appState.catalog.loads.max { $0.parsedAt < $1.parsedAt }
        attach = CameraAttachContext.fromLatestLoad(
            loadId: nil,
            tripId: latest?.tripId,
            loadDate: latest?.attachmentDateISO()
        )
    }

    private func process(_ image: UIImage) async {
        if isProcessing {
            errorMessage = String(localized: "camera.busy")
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        let timestamp = Date()
        let fix = await locationProvider.currentLocation()
        let stamp = await PhotoGeotag.stamp(for: fix)
        let unknownLabel = locale.language.languageCode?.identifier == "fr"
            ? String(localized: "media.location.unknown", locale: locale)
            : PhotoCapture.unknownLabel
        let lines = PhotoCapture.watermarkLines(
            title: attach.tripId,
            tripId: attach.tripId,
            timestamp: timestamp,
            location: stamp,
            unknownLabel: unknownLabel
        )
        guard let jpeg = PhotoImageWriter.jpeg(from: image, lines: lines),
              let preview = UIImage(data: jpeg)
        else {
            errorMessage = String(localized: "camera.decodeFailed")
            return
        }
        let fields = StoredPhotoFields.make(
            tripId: attach.tripId,
            loadDate: attach.loadDate,
            location: stamp,
            timestamp: timestamp,
            loadId: attach.loadId
        )
        let store = MediaStore(scope: appState.persistence.scope)
        let repository = appState.mediaRepository(store: store)
        do {
            var saved = false
            var recordID: UUID?
            let url: URL
            if attach.isAttachedToLoad {
                let photo = try repository.savePhoto(fields: fields, jpeg: jpeg, load: load)
                saved = true
                recordID = photo.id
                url = store.url(for: fields.fileName, kind: .photo)
            } else {
                url = try store.write(jpeg, fileName: fields.fileName, kind: .photo)
            }
            photos.append(
                SessionPhoto(
                    id: UUID(),
                    fileURL: url,
                    image: preview,
                    location: stamp,
                    timestamp: timestamp,
                    fields: fields,
                    savedToDatabase: saved,
                    recordID: recordID
                )
            )
        } catch {
            errorMessage = String(localized: "camera.saveFailed")
        }
    }

    private func removePhoto(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        let removed = photos.remove(at: index)
        let store = MediaStore(scope: appState.persistence.scope)
        store.delete(fileName: removed.fields.fileName, filePath: removed.fields.filePath, kind: .photo)
        if removed.savedToDatabase, let recordID = removed.recordID,
           let photo = appState.catalog.photos.first(where: { $0.id == recordID }) {
            try? appState.mediaRepository(store: store).delete(photo)
        }
        if photos.isEmpty { reviewing = false }
    }

    private func requestLeave() {
        if PhotoCapture.needsDiscardConfirmation(
            anySavedToDatabase: photos.contains(where: \.savedToDatabase),
            attachedToLoad: attach.isAttachedToLoad
        ) {
            confirmDiscard = true
        } else {
            discard(removeAttached: false)
        }
    }

    private func discard(removeAttached: Bool) {
        let store = MediaStore(scope: appState.persistence.scope)
        let repository = appState.mediaRepository(store: store)
        for photo in photos where !photo.savedToDatabase || removeAttached {
            store.delete(fileName: photo.fields.fileName, filePath: photo.fields.filePath, kind: .photo)
            if photo.savedToDatabase, let recordID = photo.recordID,
               let row = appState.catalog.photos.first(where: { $0.id == recordID }) {
                try? repository.delete(row)
            }
        }
        photos = []
        reviewing = false
        dismiss()
    }

    private func persistAll(thenShare: Bool) async {
        guard !photos.isEmpty, !isProcessing else { return }
        if photos.allSatisfy(\.savedToDatabase) {
            if thenShare { presentShare() } else { dismiss() }
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        let store = MediaStore(scope: appState.persistence.scope)
        let repository = appState.mediaRepository(store: store)
        do {
            for index in photos.indices where !photos[index].savedToDatabase {
                let item = photos[index]
                let data = try Data(contentsOf: item.fileURL)
                let photo = try repository.savePhoto(fields: item.fields, jpeg: data, load: nil)
                photos[index].savedToDatabase = true
                photos[index].recordID = photo.id
            }
            if thenShare {
                presentShare()
            } else {
                dismiss()
            }
        } catch {
            errorMessage = String(localized: "camera.saveFailed")
        }
    }

    private func presentShare() {
        shareItems = photos.map(\.fileURL)
        isSharing = true
    }
}

/// `UIImagePickerController` for the photo library. The live camera is `CameraCaptureController`.
struct ImagePicker: UIViewControllerRepresentable {

    let sourceType: UIImagePickerController.SourceType
    let onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onImage: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onImage = onImage
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                onImage(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}

struct ActivityShare: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
