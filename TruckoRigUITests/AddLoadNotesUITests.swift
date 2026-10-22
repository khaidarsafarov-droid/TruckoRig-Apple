import XCTest

/// Focuses the notes field opened from Add load and checks the keyboard does not cover it.
///
/// The launch argument matches `UITestLaunch.argument`. It skips onboarding and the first-run offer.
final class AddLoadNotesUITests: XCTestCase {
    private let launchArgument = "-TruckoRigUITest"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNotesFieldStaysHittableWhenFocused() {
        let app = XCUIApplication()
        app.launchArguments = [launchArgument]
        app.launch()

        let addLoad = app.buttons["journal.addLoad"]
        if !addLoad.waitForExistence(timeout: 20) {
            app.buttons["uitest.menu"].tap()
        }
        XCTAssertTrue(addLoad.waitForExistence(timeout: 8))
        addLoad.tap()

        let addPickup = app.buttons["uitest.addPickup"]
        XCTAssertTrue(addPickup.waitForExistence(timeout: 8))
        addPickup.tap()

        let stop = app.buttons["uitest.stopRow"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        stop.tap()

        let notes = waitForNotes(app)
        if !notes.isHittable {
            app.swipeUp()
        }
        notes.tap()

        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: 4) {
            let aboveKeyboard = NSPredicate { _, _ in
                let field = self.notesField(app)
                guard field.exists, field.isHittable else { return false }
                return field.frame.maxY <= keyboard.frame.minY + 8
            }
            wait(for: [XCTNSPredicateExpectation(predicate: aboveKeyboard, object: nil)], timeout: 5)
            let focused = notesField(app)
            XCTAssertTrue(focused.isHittable)
            XCTAssertLessThanOrEqual(focused.frame.maxY, keyboard.frame.minY + 8)
            focused.typeText("Dock4")
        } else {
            XCTAssertTrue(notesField(app).isHittable)
        }
        XCTAssertTrue(notesField(app).isHittable)
    }

    private func notesField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["addLoad.notes"]
        if field.exists { return field }
        return app.textViews["addLoad.notes"]
    }

    private func waitForNotes(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["addLoad.notes"]
        let view = app.textViews["addLoad.notes"]
        let appeared = NSPredicate { _, _ in field.exists || view.exists }
        wait(for: [XCTNSPredicateExpectation(predicate: appeared, object: nil)], timeout: 8)
        return field.exists ? field : view
    }
}
