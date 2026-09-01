import SwiftData
import SwiftUI
import UIKit

/// Takes a geotagged photo and attaches it to a load.
struct CameraView: View {

    var load: Load? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var location = LocationProvider()
    @State private var capturedImage: UIImage?
    @State private var isPresentingCamera = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: Spacing.section) {
            if let capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))

                if location.isAuthorized {
                    Label("camera.geotagged", systemImage: "location.fill")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }

                HStack(spacing: Spacing.standard) {
                    SoftButton(title: "camera.retake", role: .secondary) {
                        self.capturedImage = nil
                        isPresentingCamera = true
                    }
                    SoftButton(title: "action.save", isLoading: isSaving) { save() }
                }
            } else {
                EmptyStateView(
                    systemImage: "camera",
                    title: "camera.title",
                    message: "camera.message",
                    actionTitle: "camera.open",
                    action: { isPresentingCamera = true }
                )
            }
        }
        .padding(Spacing.standard)
        .frame(maxHeight: .infinity, alignment: .top)
        .forestBackground()
        .navigationTitle("screen.camera")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $isPresentingCamera) {
            ImagePicker(sourceType: .camera) { image in
                capturedImage = image
            }
            .ignoresSafeArea()
        }
        .task {
            location.requestAuthorization()
        }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private func save() {
        guard let capturedImage, !isSaving else { return }
        isSaving = true
        Task {
            let fix = await location.currentLocation()
            let repository = MediaRepository(
                context: modelContext,
                sync: appState.sync,
                store: MediaStore(scope: appState.persistence.scope)
            )
            do {
                try repository.savePhoto(
                    capturedImage,
                    attachedTo: load,
                    latitude: fix?.coordinate.latitude,
                    longitude: fix?.coordinate.longitude
                )
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// `UIImagePickerController` bridged to SwiftUI, falling back to the library on a simulator with
/// no camera.
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
