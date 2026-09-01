import SwiftData
import SwiftUI
import UIKit

/// Grid of photos and scans, optionally filtered to one load.
struct GalleryView: View {

    var load: Load? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Photo.timestamp, order: .reverse) private var allPhotos: [Photo]
    @Query(sort: \Scan.timestamp, order: .reverse) private var allScans: [Scan]

    @State private var section: MediaSection = .photos
    @State private var preview: GalleryItem?
    @State private var errorMessage: String?

    enum MediaSection: String, CaseIterable, Identifiable {
        case photos
        case scans

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .photos: return "gallery.photos"
            case .scans: return "gallery.scans"
            }
        }
    }

    private var store: MediaStore { MediaStore(scope: appState.persistence.scope) }

    private var photos: [Photo] {
        guard let load else { return allPhotos }
        return allPhotos.filter { $0.load?.id == load.id }
    }

    private var scans: [Scan] {
        guard let load else { return allScans }
        return allScans.filter { $0.load?.id == load.id }
    }

    private var items: [GalleryItem] {
        switch section {
        case .photos:
            return photos.map { GalleryItem(id: $0.id, fileName: $0.fileName, kind: .photo, timestamp: $0.timestamp, subtitle: $0.caption) }
        case .scans:
            return scans.map { GalleryItem(id: $0.id, fileName: $0.fileName, kind: .scan, timestamp: $0.timestamp, subtitle: $0.title) }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            Picker("gallery.section", selection: $section) {
                ForEach(MediaSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(Spacing.standard)

            if items.isEmpty {
                EmptyStateView(
                    systemImage: "photo.on.rectangle",
                    title: "gallery.empty.title",
                    message: "gallery.empty.message"
                )
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(items) { item in
                        Button { preview = item } label: {
                            GalleryThumbnail(item: item, store: store)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { delete(item) } label: {
                                Label("action.delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.standard)
            }
        }
        .forestBackground()
        .navigationTitle("screen.gallery")
        .sheet(item: $preview) { item in
            GalleryPreviewView(item: item, store: store)
        }
        .alert(
            "error.title",
            isPresented: .constant(errorMessage != nil),
            actions: { Button("action.ok") { errorMessage = nil } },
            message: { Text(errorMessage ?? "") }
        )
    }

    private func delete(_ item: GalleryItem) {
        let repository = MediaRepository(context: modelContext, sync: appState.sync, store: store)
        do {
            switch item.kind {
            case .photo:
                if let photo = photos.first(where: { $0.id == item.id }) { try repository.delete(photo) }
            case .scan:
                if let scan = scans.first(where: { $0.id == item.id }) { try repository.delete(scan) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One tile in the gallery grid, independent of whether it came from a photo or a scan.
struct GalleryItem: Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let kind: MediaStore.Kind
    let timestamp: Date
    let subtitle: String?
}

/// Thumbnail cell. Decodes at grid size so scrolling a long gallery stays cheap.
struct GalleryThumbnail: View {
    let item: GalleryItem
    let store: MediaStore

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.forestSurfaceMuted
                ProgressView()
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: item.id) {
            image = store.thumbnail(named: item.fileName, kind: item.kind)
        }
        .accessibilityLabel(item.subtitle ?? DateUtils.mediumDate(item.timestamp))
    }
}

/// Full-size viewer.
struct GalleryPreviewView: View {
    let item: GalleryItem
    let store: MediaStore

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .forestBackground()
            .navigationTitle(item.subtitle ?? DateUtils.mediumDate(item.timestamp))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
        .task {
            image = store.loadImage(named: item.fileName, kind: item.kind)
        }
    }
}
