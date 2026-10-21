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

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.standard) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(minHeight: 104)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    }

    private var placeSummary: String {
        guard let first = photos.first else { return "" }
        let place = first.location.cityStateLine
        let when = PhotoMetadataDisplay.dateLine(timestamp: first.timestamp)
        return "\(place) · \(when)"
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
