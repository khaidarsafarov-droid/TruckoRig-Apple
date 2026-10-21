import SwiftUI
import UIKit
import PhotosUI

/// Camera and gallery buttons used by diesel, paycheck, maintenance and other expenses.
struct ReceiptCaptureButtons: View {
    var onImage: (UIImage) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var isShowingCamera = false

    var body: some View {
        HStack(spacing: Spacing.standard) {
            Button {
                isShowingCamera = true
            } label: {
                Label("receipt.camera", systemImage: "camera")
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("receipt.gallery", systemImage: "photo")
            }
        }
        .font(.appCaptionMedium)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onImage(image)
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraImagePicker { image in
                isShowingCamera = false
                if let image { onImage(image) }
            }
            .ignoresSafeArea()
        }
    }
}

/// System camera. Falls back to the photo library when the device has no camera (the simulator).
struct CameraImagePicker: UIViewControllerRepresentable {
    var onImage: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }
    }
}
