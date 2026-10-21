import AVFoundation
import SwiftUI
import UIKit

extension CameraFlashMode {
    var captureFlash: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }
}

/// Live back-camera preview. The simulator has no camera; the screen then offers the photo library.
struct CameraCaptureController: UIViewControllerRepresentable {
    var flash: CameraFlashMode
    var captureID: Int
    var onImage: (UIImage) -> Void
    var onFailure: () -> Void

    func makeUIViewController(context: Context) -> CameraPreviewController {
        let controller = CameraPreviewController()
        controller.onImage = onImage
        controller.onFailure = onFailure
        return controller
    }

    func updateUIViewController(_ controller: CameraPreviewController, context: Context) {
        controller.flash = flash
        controller.onImage = onImage
        controller.onFailure = onFailure
        if context.coordinator.lastCaptureID != captureID {
            context.coordinator.lastCaptureID = captureID
            if captureID > 0 { controller.capture() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastCaptureID = 0
    }
}

final class CameraPreviewController: UIViewController, AVCapturePhotoCaptureDelegate {
    static var isCameraAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    var flash: CameraFlashMode = .off
    var onImage: ((UIImage) -> Void)?
    var onFailure: (() -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "truckorig.camera")
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() {
        guard session.isRunning else {
            onFailure?()
            return
        }
        let settings = AVCapturePhotoSettings()
        let mode = flash.captureFlash
        if output.supportedFlashModes.contains(mode) {
            settings.flashMode = mode
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.onFailure?() }
            return
        }
        DispatchQueue.main.async { self.onImage?(image) }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output)
        else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        queue.async { [session] in session.startRunning() }
    }
}
