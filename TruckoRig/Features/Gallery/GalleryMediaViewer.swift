import SwiftUI
import UIKit

/// One load's photos or scans. A tap opens the full-screen viewer; Select shares several files.
struct GalleryLoadGrid: View {
    let title: String
    let items: [GalleryItem]
    let store: MediaStore

    @Environment(AppState.self) private var appState
    @State private var viewerIndex: Int?
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var shareURLs: [URL] = []
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            if items.isEmpty {
                EmptyStateView(
                    systemImage: "photo.on.rectangle",
                    title: "gallery.empty.title",
                    message: "gallery.empty.message"
                )
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            if selecting {
                                toggle(item.id)
                            } else {
                                viewerIndex = index
                            }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                GalleryThumbnail(item: item, store: store)
                                if selecting {
                                    Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color.forestOnPrimary, Color.forestPrimary)
                                        .padding(6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.standard)
            }
        }
        .forestBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "action.done" : "gallery.select") {
                    selecting.toggle()
                    if !selecting { selected = [] }
                }
            }
            if selecting, !selected.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("camera.share") { share(items.filter { selected.contains($0.id) }) }
                }
            }
        }
        .fullScreenCover(isPresented: viewerPresented) {
                GalleryPageViewer(
                    items: items,
                    index: viewerSelection,
                    store: store,
                    onDelete: deleteFromViewer,
                    onClose: { viewerIndex = nil }
                )
            .environment(appState)
        }
        .sheet(isPresented: sharePresented) {
            ActivityShare(items: shareURLs)
        }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private var viewerPresented: Binding<Bool> {
        Binding(get: { viewerIndex != nil }, set: { if !$0 { viewerIndex = nil } })
    }

    private var viewerSelection: Binding<Int> {
        Binding(
            get: { min(viewerIndex ?? 0, max(items.count - 1, 0)) },
            set: { viewerIndex = $0 }
        )
    }

    private var sharePresented: Binding<Bool> {
        Binding(get: { !shareURLs.isEmpty }, set: { if !$0 { shareURLs = [] } })
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func share(_ chosen: [GalleryItem]) {
        let urls = chosen.compactMap { item -> URL? in
            let url = store.url(for: item.fileName, kind: item.kind)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if urls.isEmpty {
            errorMessage = String(localized: "gallery.fileMissing")
        } else {
            shareURLs = urls
        }
    }

    private func deleteFromViewer(_ index: Int) {
        guard items.indices.contains(index) else { return }
        delete(items[index])
        if items.count <= 1 {
            viewerIndex = nil
        } else if index >= items.count - 1 {
            viewerIndex = items.count - 2
        }
    }

    private func delete(_ item: GalleryItem) {
        let repository = appState.mediaRepository(store: store)
        do {
            switch item.kind {
            case .photo:
                if let photo = appState.catalog.photos.first(where: { $0.id == item.id })
                    ?? appState.catalog.loads.compactMap({ $0.photos?.first { $0.id == item.id } }).first {
                    try repository.delete(photo)
                }
            case .scan:
                if let scan = appState.catalog.scans.first(where: { $0.id == item.id })
                    ?? appState.catalog.loads.compactMap({ $0.scans?.first { $0.id == item.id } }).first {
                    try repository.delete(scan)
                }
            }
            selected.remove(item.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Paged viewer: pinch zoom, swipe between items, swipe down to close, delete, and share.
struct GalleryPageViewer: View {
    let items: [GalleryItem]
    @Binding var index: Int
    let store: MediaStore
    var onDelete: (Int) -> Void
    var onClose: () -> Void

    @State private var zoomed = false
    @State private var shareURLs: [URL] = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                    GalleryZoomPage(item: item, store: store) { zoomed = $0 }
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
            VStack {
                HStack {
                    viewerButton("xmark", label: "action.cancel", action: onClose)
                    Spacer()
                    if items.indices.contains(index) {
                        viewerButton("square.and.arrow.up", label: "camera.share") {
                            shareCurrent()
                        }
                    }
                    viewerButton("trash", label: "action.delete") { onDelete(index) }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: sharePresented) {
            ActivityShare(items: shareURLs)
        }
        .simultaneousGesture(closeDrag)
        .onChange(of: index) { _, _ in zoomed = false }
    }

    private var sharePresented: Binding<Bool> {
        Binding(get: { !shareURLs.isEmpty }, set: { if !$0 { shareURLs = [] } })
    }

    private func shareCurrent() {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        let url = store.url(for: item.fileName, kind: item.kind)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        shareURLs = [url]
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard !zoomed else { return }
                let down = value.translation.height
                if down > 110, down > abs(value.translation.width) {
                    onClose()
                }
            }
    }

    private func viewerButton(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .accessibilityLabel(label)
    }
}

private struct GalleryZoomPage: View {
    let item: GalleryItem
    let store: MediaStore
    var onZoomed: (Bool) -> Void

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
            } else {
                Text(item.fileName)
                    .foregroundStyle(Color.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    let next = min(max(baseScale * value.magnification, 1), 4)
                    scale = next
                    onZoomed(next > 1.01)
                }
                .onEnded { _ in
                    if scale <= 1.01 {
                        scale = 1
                        baseScale = 1
                        onZoomed(false)
                    } else {
                        baseScale = scale
                        onZoomed(true)
                    }
                }
        )
        .task(id: item.id) {
            image = store.loadImage(named: item.fileName, filePath: item.filePath, kind: item.kind)
        }
    }
}
