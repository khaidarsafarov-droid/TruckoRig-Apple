import PhotosUI
import SwiftUI
import UIKit
import VisionKit

/// Document scanner. VisionKit supplies the page images; the file on disk is one PDF, named and
/// filed like Android `PDFGenerator` / `ScanRepository`.
struct ScannerView: View {

    var load: Load? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var session: [ScanPiece] = []
    @State private var pending: ScanPiece?
    @State private var isProcessing = false
    @State private var isPresentingScanner = false
    @State private var showLibrary = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var shareURL: URL?
    @State private var isSharing = false
    @State private var didLaunch = false

    private var attached: Bool { load != nil }
    private var tripId: String? { load?.tripId }
    private var loadDate: String? { load?.attachmentDateISO() }
    private var loadId: String? { load?.id.uuidString }

    var body: some View {
        Group {
            if let pending {
                ScanResultView(
                    pending: pending,
                    sessionCount: session.count,
                    isAttachedToLoad: attached,
                    onCategory: { category in
                        guard self.pending?.savedToDatabase != true else { return }
                        self.pending?.category = category
                    },
                    onSave: { Task { await persist(finishAfter: attached) } },
                    onShare: {
                        shareURL = pending.fileURL
                        isSharing = true
                    },
                    onSaveToFiles: {
                        shareURL = pending.fileURL
                        isSharing = true
                        Task { await persist(finishAfter: false) }
                    },
                    onAddAnother: { isPresentingScanner = true },
                    onLibrary: { showLibrary = true }
                )
            } else if VNDocumentCameraViewController.isSupported {
                EmptyStateView(
                    systemImage: "doc.viewfinder",
                    title: "scanner.title",
                    message: "scanner.message",
                    actionTitle: "scanner.open",
                    action: { isPresentingScanner = true }
                )
                .padding(Spacing.standard)
            } else {
                EmptyStateView(
                    systemImage: "doc.viewfinder",
                    title: "scanner.unavailable",
                    message: "scanner.unavailableMessage",
                    actionTitle: "camera.openLibrary",
                    action: { showLibrary = true }
                )
                .padding(Spacing.standard)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .forestBackground()
        .premiumGated("premium.locked.scanner")
        .navigationTitle(pending == nil ? "scanner.title" : "scanner.results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("action.cancel") {
                    discardUnsaved()
                    dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: $isPresentingScanner) {
            DocumentScanner(
                onScan: { pages in Task { await accept(pages) } },
                onCancel: {
                    if session.isEmpty { errorMessage = String(localized: "scanner.cancelled") }
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            LibraryPagePicker(limit: ScanCapture.pageLimit) { images in
                Task { await accept(images) }
            }
        }
        .sheet(isPresented: $isSharing) {
            if let shareURL {
                ActivityShare(items: [shareURL])
            }
        }
        .loadingOverlay(isProcessing, message: "scanner.processing")
        .task {
            guard !didLaunch else { return }
            didLaunch = true
            if VNDocumentCameraViewController.isSupported {
                isPresentingScanner = true
            }
        }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
        .alert(
            "scanner.saved",
            isPresented: .isPresented($statusMessage),
            actions: { Button("action.ok") {} },
            message: { Text(statusMessage ?? "") }
        )
    }

    private func accept(_ images: [UIImage]) async {
        let pages = Array(images.prefix(ScanCapture.pageLimit))
        guard !pages.isEmpty, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        let timestamp = Date()
        var texts: [String] = []
        for page in pages {
            let recognition = await OCRService.recognizeText(in: page)
            texts.append(recognition?.text ?? "")
        }
        let ocr = ScanCapture.joinPageText(texts)
        let pdf = ScanPDFWriter.pdf(from: pages)
        guard !pdf.isEmpty else {
            errorMessage = String(localized: "scanner.error")
            return
        }
        let fields = StoredScanFields.make(
            tripId: tripId,
            loadDate: loadDate,
            timestamp: timestamp,
            fileSizeBytes: Int64(pdf.count),
            pageCount: pages.count,
            ocrText: ocr,
            loadId: loadId,
            category: nil
        )
        let store = MediaStore(scope: appState.persistence.scope)
        do {
            let url = try store.write(pdf, fileName: fields.fileName, kind: .scan)
            let piece = ScanPiece(
                fileURL: url,
                fileName: fields.fileName,
                filePath: fields.filePath,
                pageCount: pages.count,
                ocrText: ocr,
                timestamp: timestamp,
                fileSizeBytes: Int64(pdf.count),
                category: ScanDocumentCategory.fromStored(fields.category),
                savedToDatabase: false,
                isMerged: false
            )
            session.append(piece)
            pending = try mergeSession(store: store, timestamp: timestamp)
        } catch {
            errorMessage = session.isEmpty
                ? String(localized: "scanner.error")
                : String(localized: "scanner.errorKeep")
        }
    }

    private func mergeSession(store: MediaStore, timestamp: Date) throws -> ScanPiece {
        guard let only = session.first, session.count == 1 else {
            let name = ScanCapture.fileName(timestamp: timestamp, tripId: tripId, loadDate: loadDate)
            let destination = store.url(for: name, kind: .scan)
            let previous = pending?.isMerged == true && pending?.savedToDatabase != true ? pending?.fileURL : nil
            guard ScanPDFWriter.merge(sources: session.map(\.fileURL), to: destination) else {
                throw MediaStoreError.encodingFailed
            }
            if let previous, previous != destination {
                try? FileManager.default.removeItem(at: previous)
            }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            let text = ScanCapture.mergedOcrText(session.map(\.ocrText))
            let category = pending?.category ?? ScanDocumentFinder.infer(loadId: loadId, fileName: name, ocrText: text)
            return ScanPiece(
                fileURL: destination,
                fileName: name,
                filePath: ScanCapture.relativePath(fileName: name),
                pageCount: session.reduce(0) { $0 + $1.pageCount },
                ocrText: text,
                timestamp: timestamp,
                fileSizeBytes: bytes,
                category: category,
                savedToDatabase: false,
                isMerged: true
            )
        }
        return only
    }

    private func persist(finishAfter: Bool) async {
        guard var pending else { return }
        if pending.savedToDatabase {
            if finishAfter { dismiss() } else { statusMessage = String(localized: "scanner.saved") }
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        let fields = StoredScanFields(
            fileName: pending.fileName,
            filePath: pending.filePath,
            timestampMillis: MediaClock.epochMillis(pending.timestamp),
            fileSizeBytes: pending.fileSizeBytes,
            pageCount: pending.pageCount,
            ocrText: pending.ocrText,
            loadId: loadId,
            category: pending.category.rawValue
        )
        let data: Data
        do {
            data = try Data(contentsOf: pending.fileURL)
            _ = try appState.mediaRepository().saveScan(fields: fields, pdf: data, load: load)
        } catch {
            errorMessage = String(localized: "scanner.errorKeep")
            return
        }
        pending.savedToDatabase = true
        self.pending = pending
        if finishAfter {
            dismiss()
        } else {
            statusMessage = String(localized: "scanner.saved")
        }
    }

    private func discardUnsaved() {
        let store = MediaStore(scope: appState.persistence.scope)
        for piece in session where !piece.savedToDatabase {
            store.delete(fileName: piece.fileName, filePath: piece.filePath, kind: .scan)
        }
        if let pending, pending.isMerged, !pending.savedToDatabase {
            store.delete(fileName: pending.fileName, filePath: pending.filePath, kind: .scan)
        }
        session = []
        self.pending = nil
    }
}

struct ScanPiece: Identifiable {
    let id = UUID()
    var fileURL: URL
    var fileName: String
    var filePath: String
    var pageCount: Int
    var ocrText: String
    var timestamp: Date
    var fileSizeBytes: Int64
    var category: ScanDocumentCategory
    var savedToDatabase: Bool
    var isMerged: Bool
}

/// Result step: name, pages, size, category, recognised text, then save or share.
struct ScanResultView: View {
    let pending: ScanPiece
    var sessionCount: Int
    var isAttachedToLoad: Bool
    var onCategory: (ScanDocumentCategory) -> Void
    var onSave: () -> Void
    var onShare: () -> Void
    var onSaveToFiles: () -> Void
    var onAddAnother: () -> Void
    var onLibrary: () -> Void

    @State private var showText = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                SoftCard {
                    Text(pending.fileName)
                        .font(.appBodyMedium)
                        .foregroundStyle(Color.forestText)
                    Text("scanner.pages \(pending.pageCount)")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    if sessionCount > 1 {
                        Text("scanner.sessionCount \(sessionCount)")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestPrimary)
                    }
                    Text("scanner.size \(ScanCapture.formatFileSize(pending.fileSizeBytes))")
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    Text(PhotoMetadataDisplay.dateLine(timestamp: pending.timestamp))
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    if isAttachedToLoad && !pending.savedToDatabase {
                        Text("scanner.sendThenSave")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("scanner.category")
                        .font(.appHeadline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ScanDocumentCategory.allCases, id: \.self) { category in
                                Button {
                                    onCategory(category)
                                } label: {
                                    Text(category.title)
                                        .font(.appCaptionMedium)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(pending.category == category ? Color.forestOnPrimary : Color.forestText)
                                        .background(
                                            pending.category == category
                                                ? AnyShapeStyle(Color.forestPrimary)
                                                : AnyShapeStyle(Color.forestSurfaceMuted),
                                            in: Capsule()
                                        )
                                }
                                .disabled(pending.savedToDatabase)
                            }
                        }
                    }
                }

                SoftCard {
                    SectionHeader(title: "scanner.recognizedText")
                    Text(languageLine)
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                    if pending.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("scanner.noText")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    } else {
                        Button(showText ? "scanner.hideText" : "scanner.showText") {
                            showText.toggle()
                        }
                        .font(.appCaptionMedium)
                        if showText {
                            Text(pending.ocrText)
                                .font(.appCaption)
                                .foregroundStyle(Color.forestTextSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                SoftButton(title: "scanner.saveApp", action: onSave)
                HStack(spacing: Spacing.standard) {
                    SoftButton(title: "scanner.share", role: .secondary, action: onShare)
                    SoftButton(title: "scanner.savePhone", role: .secondary, action: onSaveToFiles)
                }
                HStack(spacing: Spacing.standard) {
                    SoftButton(title: "scanner.addAnother", role: .secondary, action: onAddAnother)
                    SoftButton(title: "camera.openLibrary", role: .secondary, action: onLibrary)
                }
            }
            .padding(Spacing.standard)
        }
    }

    private var languageLine: String {
        switch ScanLanguageDetector.detect(pending.ocrText) {
        case "ru": return String(localized: "scanner.language.ru")
        case "en": return String(localized: "scanner.language.en")
        case "mixed": return String(localized: "scanner.language.mixed")
        default: return String(localized: "scanner.noText")
        }
    }
}

extension ScanDocumentCategory {
    var title: LocalizedStringKey {
        switch self {
        case .load: return "scanner.category.load"
        case .paycheck: return "scanner.category.paycheck"
        case .diesel: return "scanner.category.diesel"
        case .truck: return "scanner.category.truck"
        case .other: return "scanner.category.other"
        }
    }

    var localizationKey: String.LocalizationValue {
        switch self {
        case .load: return "scanner.category.load"
        case .paycheck: return "scanner.category.paycheck"
        case .diesel: return "scanner.category.diesel"
        case .truck: return "scanner.category.truck"
        case .other: return "scanner.category.other"
        }
    }
}

/// `VNDocumentCameraViewController` bridged to SwiftUI.
struct DocumentScanner: UIViewControllerRepresentable {

    let onScan: ([UIImage]) -> Void
    var onCancel: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: ([UIImage]) -> Void
        private let onCancel: () -> Void
        private let onFinish: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void, onFinish: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
            self.onFinish = onFinish
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let limit = ScanCapture.cappedPageCount(scan.pageCount)
            let pages = (0..<limit).map { scan.imageOfPage(at: $0) }
            onScan(pages)
            onFinish()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
            onFinish()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            AppLog.media.error("Document scan failed")
            onCancel()
            onFinish()
        }
    }
}

/// Gallery import, the iOS stand-in for ML Kit `setGalleryImportAllowed(true)`.
struct LibraryPagePicker: UIViewControllerRepresentable {
    var limit: Int
    var onImages: ([UIImage]) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = limit
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(limit: limit, onImages: onImages, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let limit: Int
        let onImages: ([UIImage]) -> Void
        let onFinish: () -> Void

        init(limit: Int, onImages: @escaping ([UIImage]) -> Void, onFinish: @escaping () -> Void) {
            self.limit = limit
            self.onImages = onImages
            self.onFinish = onFinish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let chosen = Array(results.prefix(limit))
            guard !chosen.isEmpty else {
                onFinish()
                return
            }
            var images: [UIImage] = []
            let group = DispatchGroup()
            for result in chosen {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    if let image = object as? UIImage {
                        images.append(image)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.onImages(images)
                self.onFinish()
            }
        }
    }
}

