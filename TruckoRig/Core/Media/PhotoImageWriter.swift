import UIKit

/// Scales a capture to 2048px on the long edge, draws the Android watermark, and encodes JPEG 90.
enum PhotoImageWriter {

    static func jpeg(from image: UIImage, lines: [String]) -> Data? {
        let scaled = scaleDown(image, maxEdge: PhotoCapture.maxEdgePixels)
        let marked = watermark(scaled, lines: lines)
        return marked.jpegData(compressionQuality: CGFloat(PhotoCapture.jpegQuality) / 100)
    }

    static func scaleDown(_ image: UIImage, maxEdge: Int) -> UIImage {
        let pixels = pixelSize(image)
        let maxDimension = max(pixels.width, pixels.height)
        guard maxDimension > CGFloat(maxEdge), maxDimension > 0 else { return upright(image) }
        let ratio = CGFloat(maxEdge) / maxDimension
        let size = CGSize(
            width: max(1, (pixels.width * ratio).rounded(.down)),
            height: max(1, (pixels.height * ratio).rounded(.down))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            upright(image).draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Top-right block: title, date, city/state, ZIP, GPS. Port of `PhotoManager.addWatermark`.
    static func watermark(_ image: UIImage, lines: [String]) -> UIImage {
        let pixels = pixelSize(image)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: pixels, format: format).image { context in
            upright(image).draw(in: CGRect(origin: .zero, size: pixels))
            let scale = pixels.width / 1080
            let padding = 40 * scale
            let lineSpacing = 14 * scale
            let textSize = max(12, 40 * scale)
            let font = UIFont.monospacedSystemFont(ofSize: textSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
            ]
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 2 * scale),
                blur: 6 * scale,
                color: UIColor.black.cgColor
            )
            var baseline = padding + font.lineHeight
            for line in lines {
                let width = (line as NSString).size(withAttributes: attributes).width
                let origin = CGPoint(x: pixels.width - padding - width, y: baseline - font.ascender)
                (line as NSString).draw(at: origin, withAttributes: attributes)
                baseline += font.lineHeight + lineSpacing
            }
        }
    }

    private static func pixelSize(_ image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    /// UIImage drawing respects orientation; rendering once clears the EXIF flag.
    private static func upright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
