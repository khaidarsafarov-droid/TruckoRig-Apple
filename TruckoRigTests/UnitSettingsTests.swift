import XCTest
@testable import TruckoRig

/// The mile/kilometer choice lives in the App Group and outranks the language after a relaunch.
final class UnitSettingsTests: XCTestCase {

    private var standardName = ""
    private var widgetName = ""
    private var standard: UserDefaults!
    private var widget: UserDefaults!

    override func setUp() {
        super.setUp()
        standardName = "units-standard-\(UUID().uuidString)"
        widgetName = "units-widget-\(UUID().uuidString)"
        standard = UserDefaults(suiteName: standardName)
        widget = UserDefaults(suiteName: widgetName)
        standard.removePersistentDomain(forName: standardName)
        widget.removePersistentDomain(forName: widgetName)
    }

    override func tearDown() {
        standard.removePersistentDomain(forName: standardName)
        widget.removePersistentDomain(forName: widgetName)
        super.tearDown()
    }

    func testFrenchWithoutChoiceUsesKilometers() {
        let settings = makeSettings()
        settings.language = .french
        XCTAssertNil(settings.explicitMeasurementSystem)
        XCTAssertEqual(settings.measurementSystem, .kilometers)
        XCTAssertEqual(widget.string(forKey: UnitPreference.resolvedKey), MeasurementSystem.kilometers.rawValue)
    }

    func testFrenchExplicitMilesSurvivesRestartAndLanguageChange() {
        let first = makeSettings()
        first.language = .french
        XCTAssertEqual(first.measurementSystem, .kilometers)
        first.chooseMeasurementSystem(.miles)

        let restarted = makeSettings()
        XCTAssertEqual(restarted.language, .french)
        XCTAssertEqual(restarted.explicitMeasurementSystem, .miles)
        XCTAssertEqual(restarted.measurementSystem, .miles)
        XCTAssertEqual(widget.string(forKey: UnitPreference.resolvedKey), MeasurementSystem.miles.rawValue)

        restarted.language = .english
        XCTAssertEqual(restarted.explicitMeasurementSystem, .miles)
        XCTAssertEqual(restarted.measurementSystem, .miles)
        restarted.language = .french
        XCTAssertEqual(restarted.measurementSystem, .miles)
    }

    func testEnglishExplicitKilometersSurvivesRestart() {
        let first = makeSettings()
        first.language = .english
        XCTAssertEqual(first.measurementSystem, .miles)
        first.chooseMeasurementSystem(.kilometers)
        first.language = .russian
        XCTAssertEqual(first.explicitMeasurementSystem, .kilometers)
        XCTAssertEqual(first.measurementSystem, .kilometers)

        let restarted = makeSettings()
        XCTAssertEqual(restarted.language, .russian)
        XCTAssertEqual(restarted.measurementSystem, .kilometers)
        XCTAssertEqual(widget.string(forKey: UnitPreference.resolvedKey), MeasurementSystem.kilometers.rawValue)
    }

    func testExistingEnglishAndRussianUsersStayOnMiles() {
        let english = makeSettings()
        english.language = .english
        XCTAssertNil(english.explicitMeasurementSystem)
        XCTAssertEqual(english.measurementSystem, .miles)

        let russian = makeSettings()
        russian.language = .russian
        XCTAssertNil(russian.explicitMeasurementSystem)
        XCTAssertEqual(russian.measurementSystem, .miles)
    }

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: standard, widgetDefaults: widget)
    }
}
