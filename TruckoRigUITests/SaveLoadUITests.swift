import XCTest

/// Types a trip and saves it. The notes UI test only focuses a field.
final class SaveLoadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSavingALoadShowsItOnTheJournal() {
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
        addLoad.tap()

        let trip = app.textFields["addLoad.tripId"]
        XCTAssertTrue(reveal(trip, in: app), "Trip ID was not on the add-load sheet.\n\(app.debugDescription)")
        trip.tap()
        trip.typeText("UITESTLOAD1")

        let rate = app.textFields["addLoad.rate"]
        XCTAssertTrue(reveal(rate, in: app), app.debugDescription)
        typeDigits(rate, "1500", in: app)

        let miles = app.textFields["addLoad.miles"]
        XCTAssertTrue(reveal(miles, in: app), app.debugDescription)
        typeDigits(miles, "400", in: app)

        let save = app.buttons["addLoad.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4), app.debugDescription)
        let enabled = NSPredicate(format: "isEnabled == true")
        wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: save)], timeout: 8)
        save.tap()

        let saved = app.staticTexts["UITESTLOAD1"]
        XCTAssertTrue(saved.waitForExistence(timeout: 12), app.debugDescription)
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
        }
        return identified
    }

    /// A decimal pad sometimes ignores `typeText`. The key fallback still enters the digits.
    private func typeDigits(_ field: XCUIElement, _ digits: String, in app: XCUIApplication) {
        field.tap()
        field.typeText(digits)
        let value = (field.value as? String) ?? ""
        if value.filter(\.isNumber).contains(digits) { return }
        for character in digits {
            let key = app.keys[String(character)]
            if key.waitForExistence(timeout: 2) {
                key.tap()
            }
        }
    }

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
}
