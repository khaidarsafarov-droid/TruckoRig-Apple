import PDFKit
import UIKit

/// One PDF per scan, A4, images scaled to the page. Android prefers the ML Kit PDF and
/// falls back to the same image-to-PDF path. VisionKit only returns images, so this is that path.
enum ScanPDFWriter {

    static let pageSize = CGSize(width: 595.2, height: 841.8)

    static func pdf(from images: [UIImage]) -> Data {
        let data = NSMutableData()
        let bounds = CGRect(origin: .zero, size: pageSize)
        UIGraphicsBeginPDFContextToData(data, bounds, nil)
        for image in images {
            UIGraphicsBeginPDFPage()
            let inset = bounds.insetBy(dx: 24, dy: 24)
            image.draw(in: aspectFit(image.size, in: inset))
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    static func merge(sources: [URL], to destination: URL) -> Bool {
        let document = PDFDocument()
        for source in sources {
            guard let part = PDFDocument(url: source) else { continue }
            for index in 0..<part.pageCount {
                guard let page = part.page(at: index) else { continue }
                document.insert(page, at: document.pageCount)
            }
        }
        guard document.pageCount > 0 else { return false }
        return document.write(to: destination)
    }

    static func firstPageImage(at url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    private static func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
