import XCTest

/// Focuses the notes field opened from Add load and checks the keyboard does not cover it.
///
/// The launch argument and environment match `UITestLaunch`. They skip onboarding and the first-run offer.
final class AddLoadNotesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNotesFieldStaysHittableWhenFocused() {
        let app = XCUIApplication()
        app.launchArguments = [UITestLaunchArgument.argument, "YES"]
        app.launchEnvironment = [UITestLaunchArgument.environmentKey: "1"]
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            let deny = alert.buttons["Don’t Allow"]
            if deny.exists {
                deny.tap()
                return true
            }
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }
        app.launch()

        let addLoad = button(app, id: "journal.addLoad", labels: ["Add load", "Добавить рейс"])
        if !addLoad.waitForExistence(timeout: 20) {
            app.buttons["uitest.menu"].tap()
        }
        XCTAssertTrue(addLoad.waitForExistence(timeout: 8), app.debugDescription)
        dismissSystemAlerts()
        addLoad.tap()

        let addPickup = button(app, id: "uitest.addPickup", labels: ["Add pickup", "Добавить PU"])
        XCTAssertTrue(reveal(addPickup, in: app), "Add pickup was not on the add-load sheet.\n\(app.debugDescription)")
        if !addPickup.isHittable {
            app.tables.firstMatch.swipeUp()
        }
        addPickup.tap()

        let stop = button(app, id: "uitest.stopRow", labels: ["PU", "Unnamed", "Без названия"])
        XCTAssertTrue(reveal(stop, in: app), "The new stop row was not on the add-load sheet.\n\(app.debugDescription)")
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

    /// The UI test bundle cannot import the app target, so the launch contract is duplicated here.
    private enum UITestLaunchArgument {
        static let argument = "-TruckoRigUITest"
        static let environmentKey = "TRUCKORIG_UI_TEST"
    }

    private func button(_ app: XCUIApplication, id: String, labels: [String]) -> XCUIElement {
        let identified = app.descendants(matching: .any)[id]
        if identified.exists { return identified }
        for label in labels {
            let match = app.buttons[label]
            if match.exists { return match }
            let text = app.staticTexts[label]
            if text.exists { return text }
        }
        return identified
    }

    /// A form builds rows lazily, so a control past the Relay editor may not exist until scrolled.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 4) { return true }
        let table = app.tables.firstMatch
        for _ in 0..<6 {
            if table.exists {
                table.swipeUp()
            } else {
                app.swipeUp()
            }
            if element.waitForExistence(timeout: 1) { return true }
        }
        return false
    }

    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 1) else { return }
        let deny = alert.buttons["Don’t Allow"]
        if deny.exists {
            deny.tap()
            return
        }
        let allow = alert.buttons["Allow"]
        if allow.exists { allow.tap() }
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
