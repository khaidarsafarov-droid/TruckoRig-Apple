import XCTest
@testable import TruckoRigDomain

final class MeasurementUnitsTests: XCTestCase {

    func testConstants() {
        XCTAssertEqual(MeasurementUnits.kilometersPerMile, 1.609344)
        XCTAssertEqual(MeasurementUnits.litersPerUSGallon, 3.785411784)
    }

    func testDistanceVolumePriceAndRateRoundTrip() {
        let samples = [0.0, 1.0, 0.25, 6.5, 40.0, 123.456, 850.0, 120_000.0]
        for value in samples {
            let kilometers = MeasurementUnits.kilometers(fromMiles: value)
            XCTAssertEqual(kilometers, value * 1.609344, accuracy: 1e-9)
            XCTAssertEqual(MeasurementUnits.miles(fromKilometers: kilometers), value, accuracy: 1e-9)

            let liters = MeasurementUnits.liters(fromGallons: value)
            XCTAssertEqual(liters, value * 3.785411784, accuracy: 1e-9)
            XCTAssertEqual(MeasurementUnits.gallons(fromLiters: liters), value, accuracy: 1e-9)

            let perLiter = MeasurementUnits.pricePerLiter(fromPricePerGallon: value)
            XCTAssertEqual(perLiter, value / 3.785411784, accuracy: 1e-9)
            XCTAssertEqual(MeasurementUnits.pricePerGallon(fromPricePerLiter: perLiter), value, accuracy: 1e-9)

            let perKilometer = MeasurementUnits.perKilometer(fromPerMile: value)
            XCTAssertEqual(perKilometer, value / 1.609344, accuracy: 1e-9)
            XCTAssertEqual(MeasurementUnits.perMile(fromPerKilometer: perKilometer), value, accuracy: 1e-9)
        }
    }

    func testFuelEconomyRoundTrip() {
        XCTAssertEqual(MeasurementUnits.litersPer100Kilometers(fromMilesPerGallon: 0), 0)
        XCTAssertEqual(MeasurementUnits.milesPerGallon(fromLitersPer100Kilometers: 0), 0)
        for mpg in [1.0, 6.8, 8.5, 15.0] {
            let metric = MeasurementUnits.litersPer100Kilometers(fromMilesPerGallon: mpg)
            let expected = (3.785411784 * 100) / (mpg * 1.609344)
            XCTAssertEqual(metric, expected, accuracy: 1e-9)
            XCTAssertEqual(
                MeasurementUnits.milesPerGallon(fromLitersPer100Kilometers: metric),
                mpg,
                accuracy: 1e-9
            )
            XCTAssertEqual(
                MeasurementUnits.storageEconomy(
                    MeasurementUnits.displayEconomy(mpg, system: .kilometers),
                    system: .kilometers
                ),
                mpg,
                accuracy: 1e-9
            )
        }
        XCTAssertEqual(MeasurementUnits.displayEconomy(6.8, system: .miles), 6.8)
    }

    func testFrenchWithoutChoiceUsesKilometers() {
        let store = makeStore()
        XCTAssertNil(store.explicit)
        XCTAssertEqual(store.resolve(languageCode: "fr"), .kilometers)
        XCTAssertEqual(store.resolve(languageCode: "fr-CA"), .kilometers)
        XCTAssertEqual(store.resolve(languageCode: "fr_FR"), .kilometers)
        XCTAssertEqual(UnitPreference.resolve(explicit: nil, languageCode: "fr-CA"), .kilometers)
    }

    func testExistingNonFrenchLanguagesStayOnMiles() {
        let store = makeStore()
        for code in ["en", "en-US", "ru", "es", "es-MX", "de", ""] {
            XCTAssertEqual(store.resolve(languageCode: code), .miles, code)
        }
        XCTAssertEqual(
            UnitPreference.languageCode(appLanguageRaw: "system", preferredLanguages: ["en-US"]),
            "en-US"
        )
        XCTAssertEqual(
            UnitPreference.resolve(
                explicit: nil,
                languageCode: UnitPreference.languageCode(appLanguageRaw: "system", preferredLanguages: ["fr-CA"])
            ),
            .kilometers
        )
        XCTAssertEqual(
            UnitPreference.resolve(
                explicit: nil,
                languageCode: UnitPreference.languageCode(appLanguageRaw: "english", preferredLanguages: ["fr-CA"])
            ),
            .miles
        )
    }

    func testFrenchExplicitMilesSurvivesRestart() {
        let name = "units-\(UUID().uuidString)"
        let first = UnitPreferenceStore(defaults: UserDefaults(suiteName: name)!)
        XCTAssertEqual(first.resolve(languageCode: "fr"), .kilometers)
        first.setExplicit(.miles)
        first.publishResolved(.miles)

        let restarted = UnitPreferenceStore(defaults: UserDefaults(suiteName: name)!)
        XCTAssertEqual(restarted.explicit, .miles)
        XCTAssertEqual(restarted.resolve(languageCode: "fr"), .miles)
        XCTAssertEqual(restarted.resolve(languageCode: "fr-CA"), .miles)
        XCTAssertEqual(restarted.resolve(languageCode: "en"), .miles)
        XCTAssertEqual(UnitPreference.readResolved(restarted.defaults), .miles)
        restarted.defaults.removePersistentDomain(forName: name)
    }

    func testEnglishExplicitKilometersSurvivesLanguageChangeAndRestart() {
        let name = "units-km-\(UUID().uuidString)"
        let first = UnitPreferenceStore(defaults: UserDefaults(suiteName: name)!)
        XCTAssertEqual(first.resolve(languageCode: "en"), .miles)
        first.setExplicit(.kilometers)

        XCTAssertEqual(first.resolve(languageCode: "en"), .kilometers)
        XCTAssertEqual(first.resolve(languageCode: "ru"), .kilometers)
        XCTAssertEqual(first.resolve(languageCode: "fr"), .kilometers)
        XCTAssertEqual(first.explicit, .kilometers)

        let restarted = UnitPreferenceStore(defaults: UserDefaults(suiteName: name)!)
        XCTAssertEqual(restarted.resolve(languageCode: "en"), .kilometers)
        XCTAssertEqual(restarted.explicit, .kilometers)
        restarted.defaults.removePersistentDomain(forName: name)
    }

    private func makeStore() -> UnitPreferenceStore {
        let name = "units-empty-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return UnitPreferenceStore(defaults: defaults)
    }
}
