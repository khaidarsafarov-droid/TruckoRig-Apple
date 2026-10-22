import SwiftUI
import XCTest
@testable import TruckoRig

final class KeyboardAvoidanceTests: XCTestCase {
    func testFieldAboveTheKeyboardNeedsNoScroll() {
        XCTAssertFalse(KeyboardAvoidance.isHidden(fieldMinY: 120, fieldMaxY: 180, visibleMinY: 100, keyboardTop: 520))
        XCTAssertNil(KeyboardAvoidance.scrollAnchor(fieldMinY: 120, fieldMaxY: 180, visibleMinY: 100, keyboardTop: 520))
    }

    func testFieldFlushWithTheClearanceStaysVisible() {
        let keyboardTop: CGFloat = 520
        let maxY = keyboardTop - KeyboardAvoidance.clearance
        XCTAssertFalse(KeyboardAvoidance.isHidden(fieldMinY: maxY - 48, fieldMaxY: maxY, visibleMinY: 100, keyboardTop: keyboardTop))
        XCTAssertNil(KeyboardAvoidance.scrollAnchor(fieldMinY: maxY - 48, fieldMaxY: maxY, visibleMinY: 100, keyboardTop: keyboardTop))
    }

    func testFieldCrossingTheKeyboardScrollsToTheBottom() {
        let keyboardTop: CGFloat = 520
        let maxY = keyboardTop - KeyboardAvoidance.clearance + 1
        XCTAssertTrue(KeyboardAvoidance.isHidden(fieldMinY: maxY - 48, fieldMaxY: maxY, visibleMinY: 100, keyboardTop: keyboardTop))
        XCTAssertEqual(
            KeyboardAvoidance.scrollAnchor(fieldMinY: maxY - 48, fieldMaxY: maxY, visibleMinY: 100, keyboardTop: keyboardTop),
            .bottom
        )
    }

    func testFieldAboveTheVisibleBandScrollsToTheTop() {
        XCTAssertTrue(KeyboardAvoidance.isHidden(fieldMinY: 40, fieldMaxY: 90, visibleMinY: 100, keyboardTop: 520))
        XCTAssertEqual(
            KeyboardAvoidance.scrollAnchor(fieldMinY: 40, fieldMaxY: 90, visibleMinY: 100, keyboardTop: 520),
            .top
        )
    }

    /// Add-load stop notes sit under the keyboard on a tall phone until the form scrolls.
    func testAddLoadNotesFieldUnderTheKeyboardAsksToScrollToBottom() {
        let hidden = KeyboardAvoidance.isHidden(fieldMinY: 640, fieldMaxY: 700, visibleMinY: 100, keyboardTop: 520)
        XCTAssertTrue(hidden)
        XCTAssertEqual(
            KeyboardAvoidance.scrollAnchor(fieldMinY: 640, fieldMaxY: 700, visibleMinY: 100, keyboardTop: 520),
            .bottom
        )
    }

    func testDoneButtonIsRequiredWhenReturnCannotDismiss() {
        XCTAssertTrue(KeyboardAvoidance.needsDoneButton(returnInsertsNewline: true, hasReturnKey: true))
        XCTAssertTrue(KeyboardAvoidance.needsDoneButton(returnInsertsNewline: false, hasReturnKey: false))
        XCTAssertFalse(KeyboardAvoidance.needsDoneButton(returnInsertsNewline: false, hasReturnKey: true))
    }

    func testMediumSheetGrowsWhileAFieldIsFocused() {
        XCTAssertEqual(KeyboardSheetDetent.resolved(resting: .medium, fieldFocused: true), .large)
        XCTAssertEqual(KeyboardSheetDetent.resolved(resting: .medium, fieldFocused: false), .medium)
        XCTAssertEqual(KeyboardSheetDetent.resolved(resting: .large, fieldFocused: false), .large)
    }
}
