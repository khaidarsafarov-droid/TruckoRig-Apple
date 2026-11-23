import XCTest
@testable import TruckoRig

/// A formatter built for one locale is reused, and a different locale does not share it.
final class DateFormatCacheTests: XCTestCase {
    func testFormatIsStablePerLocale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let english = Locale(identifier: "en_US")
        let russian = Locale(identifier: "ru_RU")
        let first = DateUtils.string(date, format: "EEEE", locale: english, calendar: calendar)
        let second = DateUtils.string(date, format: "EEEE", locale: english, calendar: calendar)
        let other = DateUtils.string(date, format: "EEEE", locale: russian, calendar: calendar)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
        XCTAssertNotEqual(first, other)
    }
}
