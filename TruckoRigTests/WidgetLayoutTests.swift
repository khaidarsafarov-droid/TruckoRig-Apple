import SwiftUI
import UIKit
import WidgetKit
import XCTest
@testable import TruckoRig

/// The approved widget has to show three labeled actions, in order, inside both home-screen sizes.
@MainActor
final class WidgetLayoutTests: XCTestCase {

    func testSmallAndMediumKeepThreeActionsInsideTheFrame() async {
        await assertFits(family: .systemSmall, size: CGSize(width: 158, height: 158), showsRemaining: false)
        await assertFits(family: .systemMedium, size: CGSize(width: 338, height: 158), showsRemaining: true)
        // The shorter iPhone cell. Content still has to stay inside it.
        await assertFits(family: .systemMedium, size: CGSize(width: 329, height: 155), showsRemaining: true)
        await assertFits(family: .systemSmall, size: CGSize(width: 155, height: 155), showsRemaining: false)
    }

    func testButtonOrderIsCameraScannerDiesel() {
        XCTAssertEqual(
            WidgetActionKind.allCases.map(\.route),
            [.camera, .scanner, .addDiesel]
        )
        XCTAssertEqual(WidgetDeepLink.route(from: WidgetActionKind.camera.url), .camera)
        XCTAssertEqual(WidgetDeepLink.route(from: WidgetActionKind.scanner.url), .scanner)
        XCTAssertEqual(WidgetDeepLink.route(from: WidgetActionKind.diesel.url), .addDiesel)
    }

    private func assertFits(family: WidgetFamily, size: CGSize, showsRemaining: Bool) async {
        let probe = WidgetLayoutProbe()
        let host = UIHostingController(
            rootView: WeeklyGoalWidgetView(snapshot: .placeholder, probe: probe, familyOverride: family)
                .environment(\.locale, Locale(identifier: "ru"))
                .frame(width: size.width, height: size.height)
                .ignoresSafeArea()
                .dynamicTypeSize(.large)
        )
        host.safeAreaRegions = []
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        UIView.setAnimationsEnabled(false)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 400_000_000)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let bounds = host.view.convert(host.view.bounds, to: nil as UIView?).insetBy(dx: -1, dy: -1)
        let ids = ["wg.gross", "wg.percent", "wg.bar", "wg.action.camera", "wg.action.scanner", "wg.action.diesel"]
        for id in ids {
            guard let frame = probe.frames[id] else {
                XCTFail("\(family) \(size) missing \(id). Have \(probe.frames.keys.sorted())")
                continue
            }
            XCTAssertFalse(frame.isEmpty, id)
            XCTAssertTrue(bounds.contains(frame), "\(id) \(frame) outside \(size) on \(family)")
        }
        let camera = probe.frames["wg.action.camera"] ?? .zero
        let scanner = probe.frames["wg.action.scanner"] ?? .zero
        let diesel = probe.frames["wg.action.diesel"] ?? .zero
        XCTAssertLessThan(camera.minX, scanner.minX)
        XCTAssertLessThan(scanner.minX, diesel.minX)
        XCTAssertLessThanOrEqual(camera.maxX, scanner.minX + 1)
        if showsRemaining {
            let remaining = probe.frames["wg.remaining"]
            XCTAssertNotNil(remaining, "medium widget should show the amount left")
            if let remaining {
                XCTAssertTrue(bounds.contains(remaining), "remaining \(remaining) outside \(size)")
            }
            XCTAssertNotNil(probe.frames["wg.week"])
            XCTAssertNotNil(probe.frames["wg.rpm"])
        } else {
            XCTAssertNil(probe.frames["wg.remaining"])
            XCTAssertNil(probe.frames["wg.rpm"])
        }
        window.isHidden = true
    }
}
