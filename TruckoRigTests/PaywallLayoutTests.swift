import UIKit
import SwiftUI
import XCTest
@testable import TruckoRig

/// iPhone SE logical size (320×568) at a large Dynamic Type size.
/// The subscribe button has to scroll into the area above the taller of the safe area and the keyboard.
@MainActor
final class PaywallLayoutTests: XCTestCase {
    func testBottomInsetIsTheLargerObstruction() {
        XCTAssertEqual(PaywallInsets.bottom(safeArea: 48, keyboard: 0), 48)
        XCTAssertEqual(PaywallInsets.bottom(safeArea: 48, keyboard: 20), 48)
        XCTAssertEqual(PaywallInsets.bottom(safeArea: 48, keyboard: 240), 240)
        XCTAssertNotEqual(PaywallInsets.bottom(safeArea: 48, keyboard: 240), 48 + 240)
    }

    func testSubscribeButtonStaysReachableOnSEWithLargeDynamicType() async {
        await assertSubscribeButtonReachable(safeArea: 48, keyboard: 0)
        await assertSubscribeButtonReachable(safeArea: 48, keyboard: 240)
    }

    private func assertSubscribeButtonReachable(safeArea: CGFloat, keyboard: CGFloat) async {
        let width: CGFloat = 320
        let height: CGFloat = 568
        let inset = PaywallInsets.bottom(safeArea: safeArea, keyboard: keyboard)
        let probe = PaywallLayoutProbe()
        let host = UIHostingController(
            rootView: PaywallView(
                priceText: "$2.99",
                includesFreeMonth: true,
                isLoading: false,
                safeAreaBottom: safeArea,
                keyboardHeight: keyboard,
                layoutProbe: probe,
                onSubscribe: {},
                onRestore: {},
                onClose: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.locale, Locale(identifier: "en"))
        )
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        UIView.setAnimationsEnabled(false)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 700_000_000)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let windowFrame = window.convert(window.bounds, to: nil)
        let button = buttonFrame(in: host.view) ?? probe.subscribeFrame
        let visibleBottom = windowFrame.maxY - inset
        XCTAssertGreaterThan(
            probe.contentHeight,
            height - inset,
            "Paywall content should scroll on a 320×568 SE at accessibility Dynamic Type (content \(probe.contentHeight), inset \(inset))"
        )
        XCTAssertGreaterThan(button.height, 1, "Subscribe button frame was \(button), window \(windowFrame)")
        XCTAssertGreaterThanOrEqual(button.minY, windowFrame.minY - 1, "button \(button) window \(windowFrame)")
        XCTAssertLessThanOrEqual(
            button.maxY,
            visibleBottom + 1,
            "Subscribe button \(button) should sit above the \(keyboard > safeArea ? "keyboard" : "safe area") (visibleBottom \(visibleBottom))"
        )
        window.isHidden = true
    }

    private func buttonFrame(in view: UIView) -> CGRect? {
        if view.accessibilityIdentifier == "paywall.subscribe", view.bounds.height > 1 {
            return view.convert(view.bounds, to: nil)
        }
        for subview in view.subviews {
            if let frame = buttonFrame(in: subview) {
                return frame
            }
        }
        return nil
    }
}
