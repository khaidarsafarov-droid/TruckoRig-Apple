import SwiftData
import SwiftUI
import UIKit
import VisionKit

/// Scans a document, runs text recognition and files it against a load.
struct ScannerView: View {

    var load: Load? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var pages: [UIImage] = []
    @State private var recognizedText: String?
    @State private var title = ""
    @State private var isPresentingScanner = true
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.section) {
                if pages.isEmpty {
                    EmptyStateView(
                        systemImage: "doc.viewfinder",
                        title: "scanner.title",
                        message: "scanner.message",
                        actionTitle: "scanner.open",
                        action: { isPresentingScanner = true }
                    )
                } else {
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                        Image(uiImage: page)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.cardRadius, style: .continuous))
                    }

                    SoftTextField(title: "scanner.documentTitle", text: $title)

                    if let recognizedText, !recognizedText.isEmpty {
                        SoftCard {
                            SectionHeader(title: "scanner.recognizedText")
                            Text(recognizedText)
                                .font(.appCaption)
                                .foregroundStyle(Color.forestTextSecondary)
                                .textSelection(.enabled)
                        }
                    }

                    HStack(spacing: Spacing.standard) {
                        SoftButton(title: "scanner.rescan", role: .secondary) {
                            pages = []
                            recognizedText = nil
                            isPresentingScanner = true
                        }
                        SoftButton(title: "action.save", isLoading: isProcessing) { save() }
                    }
                }
            }
            .padding(Spacing.standard)
        }
        .forestBackground()
        .navigationTitle("screen.scanner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $isPresentingScanner) {
            DocumentScanner { scanned in
                pages = scanned
                Task { await recognize() }
            }
            .ignoresSafeArea()
        }
        .loadingOverlay(isProcessing, message: "scanner.processing")
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private func recognize() async {
        guard let first = pages.first else { return }
        isProcessing = true
        defer { isProcessing = false }
        guard let result = await OCRService.recognizeText(in: first) else { return }
        recognizedText = result.text
        if title.isEmpty, let suggestion = OCRService.suggestedTitle(from: result.text) {
            title = suggestion
        }
    }

    private func save() {
        guard !pages.isEmpty else { return }
        isProcessing = true
        let repository = MediaRepository(
            context: modelContext,
            sync: appState.sync,
            store: MediaStore(scope: appState.persistence.scope)
        )
        do {
            // Each page becomes its own scan; the recognised text belongs to the page it came from.
            for (index, page) in pages.enumerated() {
                try repository.saveScan(
                    page,
                    attachedTo: load,
                    ocrText: index == 0 ? recognizedText : nil,
                    title: title.nonEmpty
                )
            }
            isProcessing = false
            dismiss()
        } catch {
            isProcessing = false
            errorMessage = error.localizedDescription
        }
    }
}

/// `VNDocumentCameraViewController` bridged to SwiftUI.
struct DocumentScanner: UIViewControllerRepresentable {

    let onScan: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: ([UIImage]) -> Void
        private let onFinish: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onFinish: @escaping () -> Void) {
            self.onScan = onScan
            self.onFinish = onFinish
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            onScan(pages)
            onFinish()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            AppLog.media.error("Document scan failed")
            onFinish()
        }
    }
}
