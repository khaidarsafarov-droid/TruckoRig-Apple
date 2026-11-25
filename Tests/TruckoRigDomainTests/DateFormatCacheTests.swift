import XCTest
@testable import TruckoRigDomain

final class DateFormatCacheTests: XCTestCase {

    private let posix = Locale(identifier: "en_US_POSIX")
    private var utc: TimeZone { TimeZone.gmt }
    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    func testPatternFormatsAndParsesRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let text = DateFormatCache.string(
            from: date,
            pattern: "yyyy-MM-dd HH:mm",
            locale: posix,
            calendar: gregorian,
            timeZone: utc
        )
        XCTAssertEqual(text, "2024-07-03 09:46")
        let parsed = DateFormatCache.date(
            from: text,
            pattern: "yyyy-MM-dd HH:mm",
            locale: posix,
            calendar: gregorian,
            timeZone: utc
        )
        XCTAssertEqual(try XCTUnwrap(parsed).timeIntervalSince1970, 1_719_999_960, accuracy: 0.5)
    }

    func testTimeZoneIsPartOfTheKey() {
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let tokyo = TimeZone(secondsFromGMT: 9 * 3600) ?? .gmt
        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = tokyo
        let utcText = DateFormatCache.string(
            from: date, pattern: "HH:mm", locale: posix, calendar: gregorian, timeZone: utc
        )
        let tokyoText = DateFormatCache.string(
            from: date, pattern: "HH:mm", locale: posix, calendar: tokyoCalendar, timeZone: tokyo
        )
        XCTAssertEqual(utcText, "09:46")
        XCTAssertEqual(tokyoText, "18:46")
    }

    func testDifferentPatternsDoNotShareAFormatter() {
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let day = DateFormatCache.string(
            from: date, pattern: "yyyy-MM-dd", locale: posix, calendar: gregorian, timeZone: utc
        )
        let compact = DateFormatCache.string(
            from: date, pattern: "yyyyMMdd_HHmmss", locale: posix, calendar: gregorian, timeZone: utc
        )
        XCTAssertEqual(day, "2024-07-03")
        XCTAssertEqual(compact, "20240703_094640")
    }

    func testConcurrentUseGivesTheSameAnswer() {
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let results = NSLock()
        var seen = Set<String>()
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            let text = DateFormatCache.string(
                from: date, pattern: "yyyy-MM-dd", locale: posix, calendar: gregorian, timeZone: utc
            )
            results.lock()
            seen.insert(text)
            results.unlock()
        }
        XCTAssertEqual(seen, ["2024-07-03"])
    }

    func testBackupFileNameStillUsesTheExportTimeZone() {
        let name = BackupSchema.jsonFileName(exportedAt: 1_720_000_000_000, timeZone: utc)
        XCTAssertEqual(name, "TruckoRig_Backup_20240703_094640.json")
    }

    func testDistanceSymbolsComeFromFoundationUnits() {
        XCTAssertEqual(MeasurementSystem.miles.distanceSymbol, "mi")
        XCTAssertEqual(MeasurementSystem.kilometers.distanceSymbol, "km")
        XCTAssertEqual(MeasurementSystem.miles.lengthUnit, UnitLength.miles)
        XCTAssertEqual(MeasurementSystem.kilometers.lengthUnit, UnitLength.kilometers)
    }

    func testWidgetAndTelegramDistanceTextKeepTheirShape() {
        XCTAssertEqual(USMoneyFormat.miles(850), "850 mi")
        XCTAssertEqual(USMoneyFormat.miles(850, system: .kilometers), "1,368 km")
        XCTAssertEqual(USMoneyFormat.rpmPerMile(2.94), "$2.94/mi")
        XCTAssertEqual(USMoneyFormat.rpmPerMile(2.94, system: .kilometers), "$1.83/km")
    }
}
