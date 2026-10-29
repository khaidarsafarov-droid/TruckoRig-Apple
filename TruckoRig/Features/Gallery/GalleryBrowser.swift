import SwiftUI
import UIKit

struct GalleryItem: Identifiable, Hashable {
    let id: UUID
    let loadID: UUID?
    let tripID: String
    let route: String
    let loadDate: Date?
    let fileName: String
    let filePath: String?
    let kind: MediaStore.Kind
    let timestamp: Date
    let subtitle: String?

    static func photos(_ photos: [Photo]) -> [GalleryItem] {
        photos.map { photo in
            GalleryItem(
                id: photo.id,
                loadID: photo.loadId ?? photo.load?.id,
                tripID: photo.load?.tripId ?? "",
                route: photo.load?.route ?? "",
                loadDate: photo.load?.date,
                fileName: photo.fileName,
                filePath: photo.filePath,
                kind: .photo,
                timestamp: photo.timestamp,
                subtitle: photo.placeLine.nonEmpty ?? photo.caption
            )
        }
    }

    static func scans(_ scans: [Scan]) -> [GalleryItem] {
        scans.map { scan in
            GalleryItem(
                id: scan.id,
                loadID: scan.loadId ?? scan.load?.id,
                tripID: scan.load?.tripId ?? "",
                route: scan.load?.route ?? "",
                loadDate: scan.load?.date,
                fileName: scan.fileName,
                filePath: scan.filePath,
                kind: .scan,
                timestamp: scan.timestamp,
                subtitle: scan.ocrText
            )
        }
    }
}

struct GalleryLoadGroup: Identifiable {
    var id: UUID
    var title: String
    var route: String
    var date: Date?
    var items: [GalleryItem]

    static let unlinkedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func make(items: [GalleryItem], loads: [Load], onlyLoadID: UUID?) -> [GalleryLoadGroup] {
        let loadsByID = Dictionary(uniqueKeysWithValues: loads.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: items) { $0.loadID ?? unlinkedID }
        return grouped.compactMap { key, rows in
            if let onlyLoadID, key != onlyLoadID { return nil }
            let load = loadsByID[key]
            let sorted = rows.sorted { $0.timestamp > $1.timestamp }
            return GalleryLoadGroup(
                id: key,
                title: load?.tripId.nonEmpty ?? sorted.first?.tripID.nonEmpty ?? String(localized: "gallery.unlinked"),
                route: load?.route.nonEmpty ?? sorted.first?.route.nonEmpty ?? "",
                date: load?.date ?? sorted.first?.loadDate,
                items: sorted
            )
        }
        .sorted { lhs, rhs in
            let left = lhs.items.first?.timestamp ?? .distantPast
            let right = rhs.items.first?.timestamp ?? .distantPast
            return left > right
        }
    }
}

struct GalleryLoadCard: View {
    let group: GalleryLoadGroup
    let store: MediaStore
    let section: GallerySection

    var body: some View {
        SoftCard {
            Text(group.title)
                .font(.appHeadline)
                .foregroundStyle(Color.forestText)
            if !group.route.isEmpty {
                Text(group.route)
                    .font(.appBody)
                    .foregroundStyle(Color.forestText)
                    .lineLimit(1)
            }
            HStack {
                if let date = group.date {
                    Text(DateUtils.weekdayShortDay(date))
                        .font(.appCaption)
                        .foregroundStyle(Color.forestTextSecondary)
                }
                Spacer()
                Text(countLabel)
                    .font(.appCaptionMedium)
                    .foregroundStyle(Color.forestPrimary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(group.items.prefix(8)) { item in
                        GalleryThumbnail(item: item, store: store, side: 56)
                    }
                }
            }
        }
    }

    private var countLabel: String {
        let count = group.items.count
        if section == .scans {
            return String(localized: "gallery.scanCount \(count)")
        }
        return String(localized: "gallery.photoCount \(count)")
    }
}

struct GalleryThumbnail: View {
    let item: GalleryItem
    let store: MediaStore
    var side: CGFloat = 104

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
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: item.id) {
            image = store.thumbnail(named: item.fileName, filePath: item.filePath, kind: item.kind, maxPixel: side * 2)
        }
    }
}
