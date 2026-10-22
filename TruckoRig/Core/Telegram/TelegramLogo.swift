import UIKit

/// Square JPEG on the Midnight plate (`#1E2150`), the same plate Android uses for `setMyProfilePhoto`.
enum TelegramLogoJPEG {
    static let side: CGFloat = 640

    static func encode() -> Data? {
        guard let image = UIImage(named: "TelegramLogo") ?? UIImage(named: "AppIcon") else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let rendered = renderer.image { context in
            UIColor(red: 30 / 255, green: 33 / 255, blue: 80 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.9) else { return nil }
        return TelegramBranding.isJPEG([UInt8](data.prefix(3))) ? data : nil
    }
}
