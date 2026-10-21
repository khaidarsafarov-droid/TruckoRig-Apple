import SwiftUI
import UIKit

/// Photos and scans. Photo filters match Android (all / today / this week / by load).
/// Scans filter by the same categories and search as `ScanDocumentFinder.matches`.
struct GalleryView: View {

    var load: Load? = nil

    @Environment(AppState.self) private var appState

    @State private var section: MediaSection = .photos
    @State private var photoFilter: PhotoFilter = .all
    @State private var loadFilterID: UUID?
    @State private var scanFilter: ScanDocumentCategory?
    @State private var scanQuery = ""
    @State private var preview: GalleryItem?
    @State private var errorMessage: String?
    @State private var didCleanOrphans = false

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

    enum PhotoFilter: String, CaseIterable, Identifiable {
        case all, today, week, byLoad
        var id: String { rawValue }
        var localizationKey: String.LocalizationValue {
            switch self {
            case .all: return "gallery.filter.all"
            case .today: return "gallery.filter.today"
            case .week: return "gallery.filter.week"
            case .byLoad: return "gallery.filter.load"
            }
        }
    }

    private var store: MediaStore { MediaStore(scope: appState.persistence.scope) }

    private var photos: [Photo] {
        let base: [Photo]
        if let load {
            base = appState.catalog.photos.filter { $0.loadId == load.id }
        } else {
            base = appState.catalog.photos
        }
        let calendar = appState.settings.truckingWeek.calendar
        let now = Date()
        return base.filter { photo in
            switch photoFilter {
            case .all:
                return true
            case .today:
                return PhotoGalleryTimeBounds.isInToday(photo.timestamp, now: now, calendar: calendar)
            case .week:
                return PhotoGalleryTimeBounds.isInThisWeek(photo.timestamp, now: now, calendar: calendar)
            case .byLoad:
                guard let loadFilterID else { return photo.loadId != nil }
                return photo.loadId == loadFilterID
            }
        }
    }

    private var scanRows: [Scan] {
        let base: [Scan]
        if let load {
            base = appState.catalog.scans.filter { $0.loadId == load.id }
        } else {
            base = appState.catalog.scans
        }
        return base.filter { scan in
            let trip = ScanListText.resolveTripId(fileName: scan.fileName, loadTripId: scan.load?.tripId)
            let route = scan.load?.route.nonEmpty
                ?? ScanListText.extractRoute(from: scan.ocrText ?? "")
                ?? "—"
            return ScanDocumentFinder.matches(
                storedCategory: scan.category,
                fileName: scan.fileName,
                ocrText: scan.ocrText ?? "",
                tripId: trip,
                routeLabel: route,
                dateLabel: ScanListText.dateLabel(timestamp: scan.timestamp),
                filter: scanFilter,
                query: scanQuery
            )
        }
    }

    private var items: [GalleryItem] {
        switch section {
        case .photos:
            return photos.map { photo in
                GalleryItem(
                    id: photo.id,
                    fileName: photo.fileName,
                    filePath: photo.filePath,
                    kind: .photo,
                    timestamp: photo.timestamp,
                    subtitle: photo.placeLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? photo.caption
                        : photo.placeLine
                )
            }
        case .scans:
            return scanRows.map { scan in
                GalleryItem(
                    id: scan.id,
                    fileName: scan.fileName,
                    filePath: scan.filePath,
                    kind: .scan,
                    timestamp: scan.timestamp,
                    subtitle: scan.documentCategory.rawValue
                )
            }
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
            .padding(.horizontal, Spacing.standard)
            .padding(.top, Spacing.standard)

            if section == .photos && load == nil {
                photoFilters
            }
            if section == .scans {
                scanFilters
            }

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
                .environment(appState)
        }
        .task {
            guard !didCleanOrphans else { return }
            didCleanOrphans = true
            _ = appState.mediaRepository(store: store).cleanupOrphanScans(known: appState.catalog.scans)
        }
        .alert(
            "error.title",
            isPresented: .isPresented($errorMessage),
            actions: { Button("action.ok") {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    private var photoFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PhotoFilter.allCases) { filter in
                        filterChip(String(localized: filter.localizationKey), selected: photoFilter == filter) {
                            photoFilter = filter
                        }
                    }
                }
                .padding(.horizontal, Spacing.standard)
            }
            if photoFilter == .byLoad {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(String(localized: "gallery.filter.allLoads"), selected: loadFilterID == nil) {
                            loadFilterID = nil
                        }
                        ForEach(appState.catalog.loads) { load in
                            filterChip(load.tripId, selected: loadFilterID == load.id) {
                                loadFilterID = load.id
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.standard)
                }
            }
        }
    }

    private var scanFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("attach.search", text: $scanQuery)
                .font(.appBody)
                .padding(.horizontal, Spacing.standard)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(String(localized: "gallery.filter.all"), selected: scanFilter == nil) { scanFilter = nil }
                    ForEach(ScanDocumentCategory.allCases, id: \.self) { category in
                        filterChip(String(localized: category.localizationKey), selected: scanFilter == category) {
                            scanFilter = category
                        }
                    }
                }
                .padding(.horizontal, Spacing.standard)
            }
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appCaptionMedium)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.forestOnPrimary : Color.forestText)
                .background(selected ? Color.forestPrimary : Color.forestSurfaceMuted, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func delete(_ item: GalleryItem) {
        let repository = appState.mediaRepository(store: store)
        do {
            switch item.kind {
            case .photo:
                if let photo = appState.catalog.photos.first(where: { $0.id == item.id }) {
                    try repository.delete(photo)
                }
            case .scan:
                if let scan = appState.catalog.scans.first(where: { $0.id == item.id }) {
                    try repository.delete(scan)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GalleryItem: Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let filePath: String?
    let kind: MediaStore.Kind
    let timestamp: Date
    let subtitle: String?
}

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
                Image(systemName: item.kind == .scan ? "doc.richtext" : "photo")
                    .foregroundStyle(Color.forestTextSecondary)
            }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: item.id) {
            image = store.thumbnail(named: item.fileName, filePath: item.filePath, kind: item.kind)
        }
        .accessibilityLabel(item.subtitle ?? DateUtils.mediumDate(item.timestamp))
    }
}

/// Full-size viewer with the same place, time and coordinate lines as Android `PhotoDetailScreen`.
struct GalleryPreviewView: View {
    let item: GalleryItem
    let store: MediaStore

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var linkedLoadID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.standard) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else if item.kind == .scan {
                        Text(item.fileName)
                            .font(.appBodyMedium)
                    } else {
                        Text("gallery.fileMissing")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                    }
                    if item.kind == .photo, let photo = currentPhoto {
                        Label(photo.placeLine, systemImage: "mappin.and.ellipse")
                            .font(.appBody)
                        Label(PhotoMetadataDisplay.dateLine(timestamp: photo.timestamp), systemImage: "calendar")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                        if let latitude = photo.latitude, let longitude = photo.longitude {
                            Label(
                                PhotoMetadataDisplay.coordinateLine(latitude: latitude, longitude: longitude),
                                systemImage: "location"
                            )
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                        }
                        Text("gallery.linkLoad")
                            .font(.appHeadline)
                        Picker("gallery.linkLoad", selection: $linkedLoadID) {
                            Text("gallery.unlinked").tag(Optional<UUID>.none)
                            ForEach(appState.catalog.loads) { load in
                                Text(load.tripId).tag(Optional(load.id))
                            }
                        }
                        .onChange(of: linkedLoadID) { _, newValue in
                            let load = appState.catalog.loads.first { $0.id == newValue }
                            try? appState.mediaRepository(store: store).attach(photo, to: load)
                        }
                    }
                    if item.kind == .scan, let scan = appState.catalog.scans.first(where: { $0.id == item.id }) {
                        Text("scanner.pages \(scan.pageCount)")
                            .font(.appCaption)
                        Text("scanner.size \(ScanCapture.formatFileSize(scan.fileSizeBytes))")
                            .font(.appCaption)
                            .foregroundStyle(Color.forestTextSecondary)
                        Text(scan.documentCategory.rawValue)
                            .font(.appCaptionMedium)
                        if let text = scan.ocrText?.nonEmpty {
                            Text(text)
                                .font(.appCaption)
                                .foregroundStyle(Color.forestTextSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(Spacing.standard)
            }
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
            image = store.loadImage(named: item.fileName, filePath: item.filePath, kind: item.kind)
            if item.kind == .photo {
                linkedLoadID = currentPhoto?.loadId
            }
        }
    }

    private var currentPhoto: Photo? {
        appState.catalog.photos.first { $0.id == item.id }
    }
}

