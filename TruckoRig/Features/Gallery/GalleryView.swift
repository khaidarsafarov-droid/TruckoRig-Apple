import SwiftUI

/// Photos and scans, grouped by the load they belong to.
struct GalleryView: View {

    var load: Load? = nil

    @Environment(AppState.self) private var appState

    @State private var section: GallerySection = .photos
    @State private var filter: GalleryTimeFilter = .all
    @State private var loadFilterID: UUID?
    @State private var scanQuery = ""

    private var store: MediaStore { MediaStore(scope: appState.persistence.scope) }

    var body: some View {
        Group {
            if let load {
                GalleryLoadGrid(
                    title: load.tripId,
                    items: items(for: load.id),
                    store: store
                )
            } else {
                library
            }
        }
        .forestBackground()
        .navigationTitle(load == nil ? Text("screen.gallery") : Text(load?.tripId ?? ""))
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.standard) {
                Picker("gallery.section", selection: $section) {
                    ForEach(GallerySection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                filters
                if section == .scans {
                    TextField("attach.search", text: $scanQuery)
                        .font(.appBody)
                }
                if groups.isEmpty {
                    EmptyStateView(
                        systemImage: "photo.on.rectangle",
                        title: "gallery.empty.title",
                        message: "gallery.empty.message"
                    )
                } else {
                    ForEach(groups) { group in
                        NavigationLink {
                            GalleryLoadGrid(title: group.title, items: group.items, store: store)
                        } label: {
                            GalleryLoadCard(group: group, store: store, section: section)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Spacing.standard)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GalleryTimeFilter.allCases) { item in
                        chip(String(localized: item.localizationKey), selected: filter == item) {
                            filter = item
                        }
                    }
                }
            }
            if filter == .byLoad {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(String(localized: "gallery.filter.allLoads"), selected: loadFilterID == nil) {
                            loadFilterID = nil
                        }
                        ForEach(appState.catalog.loads) { load in
                            chip(load.tripId, selected: loadFilterID == load.id) {
                                loadFilterID = load.id
                            }
                        }
                    }
                }
            }
        }
    }

    private var groups: [GalleryLoadGroup] {
        GalleryLoadGroup.make(
            items: filteredItems,
            loads: appState.catalog.loads,
            onlyLoadID: filter == .byLoad ? loadFilterID : nil
        )
    }

    private func items(for loadID: UUID) -> [GalleryItem] {
        collected.filter { $0.loadID == loadID }
    }

    private var filteredItems: [GalleryItem] {
        let calendar = appState.settings.truckingWeek.calendar
        let now = Date()
        return collected.filter { item in
            if section == .scans, !scanQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let hay = [item.fileName, item.subtitle ?? "", item.tripID, item.route].joined(separator: " ")
                if !hay.localizedCaseInsensitiveContains(scanQuery.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return false
                }
            }
            switch filter {
            case .all, .byLoad:
                return true
            case .today:
                return PhotoGalleryTimeBounds.isInToday(item.timestamp, now: now, calendar: calendar)
            case .week:
                return PhotoGalleryTimeBounds.isInThisWeek(item.timestamp, now: now, calendar: calendar)
            }
        }
    }

    /// Catalog rows plus anything already hanging off a load, so a just-saved photo is not missed.
    private var collected: [GalleryItem] {
        switch section {
        case .photos:
            return GalleryItem.photos(mergedPhotos)
        case .scans:
            return GalleryItem.scans(mergedScans)
        }
    }

    private var mergedPhotos: [Photo] {
        var byID: [UUID: Photo] = [:]
        for photo in appState.catalog.photos { byID[photo.id] = photo }
        for load in appState.catalog.loads {
            for photo in load.photos ?? [] {
                if photo.loadId == nil { photo.loadId = load.id }
                photo.load = load
                byID[photo.id] = photo
            }
        }
        return byID.values.sorted { $0.timestamp > $1.timestamp }
    }

    private var mergedScans: [Scan] {
        var byID: [UUID: Scan] = [:]
        for scan in appState.catalog.scans { byID[scan.id] = scan }
        for load in appState.catalog.loads {
            for scan in load.scans ?? [] {
                if scan.loadId == nil { scan.loadId = load.id }
                scan.load = load
                byID[scan.id] = scan
            }
        }
        return byID.values.sorted { $0.timestamp > $1.timestamp }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.appCaptionMedium)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.forestOnPrimary : Color.forestText)
                .background(
                    selected ? AnyShapeStyle(Color.forestPrimary) : AnyShapeStyle(Color.forestSurfaceMuted),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

enum GallerySection: String, CaseIterable, Identifiable {
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

enum GalleryTimeFilter: String, CaseIterable, Identifiable {
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
