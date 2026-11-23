import SwiftUI
import UIKit

/// Principal class for the share extension. SwiftUI draws the sheet; UIKit owns the extension context.
final class ShareViewController: UIViewController {
    private let model = ShareExtensionModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        AppLocale.install()
        AppLocale.applyStoredWidgetLanguage()
        view.backgroundColor = UIColor(red: 13 / 255, green: 15 / 255, blue: 30 / 255, alpha: 1)
        preferredContentSize = CGSize(width: 0, height: 320)

        let host = UIHostingController(rootView: ShareExtensionScreen(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        model.start(context: extensionContext)
    }
}
