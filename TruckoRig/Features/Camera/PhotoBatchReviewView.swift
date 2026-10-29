import SwiftUI
import UIKit

/// Grid of the photos taken in this session, before or after they are written to the journal.
struct PhotoBatchReviewView: View {
    let photos: [SessionPhoto]
    var isSaving: Bool
    var onAddMore: () -> Void
    var onRemove: (Int) -> Void
    var onSaveAll: () -> Void
    var onShare: () -> Void

    @State private var viewerIndex: Int?

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    ZStack(alignment: .topTrailing) {
                        Button {
                            viewerIndex = index
                        } label: {
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(minHeight: 104)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(caption(photo)))
                        Button {
                            onRemove(index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.forestOnPrimary, Color.forestPrimary)
                                .font(.title3)
                        }
                        .padding(4)
                        .accessibilityLabel("action.delete")
                    }
                }
            }
            Text(placeSummary)
                .font(.appCaption)
                .foregroundStyle(Color.forestTextSecondary)
            SoftButton(title: "camera.saveAll", isLoading: isSaving, action: onSaveAll)
            HStack(spacing: Spacing.standard) {
                SoftButton(title: "camera.addMore", role: .secondary, action: onAddMore)
                SoftButton(title: "camera.share", role: .secondary, action: onShare)
            }
        }
        .fullScreenCover(isPresented: viewerPresented) {
            SessionPhotoViewer(
                photos: photos,
                index: viewerSelection,
                onDelete: deleteFromViewer,
                onClose: { viewerIndex = nil }
            )
        }
    }

    private var viewerPresented: Binding<Bool> {
        Binding(get: { viewerIndex != nil }, set: { if !$0 { viewerIndex = nil } })
    }

    private var viewerSelection: Binding<Int> {
        Binding(
            get: { min(viewerIndex ?? 0, max(photos.count - 1, 0)) },
            set: { viewerIndex = $0 }
        )
    }

    private func deleteFromViewer(_ index: Int) {
        let remaining = photos.count - 1
        onRemove(index)
        if remaining <= 0 {
            viewerIndex = nil
        } else if index >= remaining {
            viewerIndex = remaining - 1
        }
    }

    private var placeSummary: String {
        guard let first = photos.first else { return "" }
        return caption(first)
    }

    private func caption(_ photo: SessionPhoto) -> String {
        let place = photo.location.cityStateLine
        let when = PhotoMetadataDisplay.dateLine(timestamp: photo.timestamp, locale: AppLocale.locale)
        return "\(place) · \(when)"
    }
}

/// Full-screen review of the photos in this capture. Android opens one shot; this also
/// pages across the batch, zooms, and deletes.
private struct SessionPhotoViewer: View {
    let photos: [SessionPhoto]
    @Binding var index: Int
    var onDelete: (Int) -> Void
    var onClose: () -> Void

    @State private var zoomed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { position, photo in
                    ZoomableSessionPhoto(image: photo.image) { zoomed = $0 }
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            VStack {
                HStack {
                    viewerButton("xmark", label: "action.cancel", action: onClose)
                    Spacer()
                    viewerButton("trash", label: "action.delete") {
                        onDelete(index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                Spacer()
                if photos.indices.contains(index) {
                    Text(photos[index].location.cityStateLine + " · " + PhotoMetadataDisplay.dateLine(timestamp: photos[index].timestamp, locale: AppLocale.locale))
                        .font(.appCaption)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 36)
                }
            }
        }
        .preferredColorScheme(.dark)
        .simultaneousGesture(closeDrag)
        .onChange(of: index) { _, _ in zoomed = false }
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

private struct ZoomableSessionPhoto: View {
    let image: UIImage
    var onZoomed: (Bool) -> Void

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
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
    }
}

struct SessionPhoto: Identifiable {
    let id: UUID
    var fileURL: URL
    var image: UIImage
    var location: LocationStamp
    var timestamp: Date
    var fields: StoredPhotoFields
    var savedToDatabase: Bool
    var recordID: UUID?
}
