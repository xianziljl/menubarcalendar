import XCTest
@testable import MenuBarCalendar

final class DateFormatterTests: XCTestCase {
    func testNormalizesWeekBasedYearAndDayOfYearTokens() {
        // YYYY/DD cause off-by-one dates around year boundaries; the app
        // rewrites them to calendar-year/day-of-month on purpose.
        XCTAssertEqual(DateFormatter.statusDateFormatter(pattern: "YYYY-MM-dd").dateFormat, "yyyy-MM-dd")
        XCTAssertEqual(DateFormatter.statusDateFormatter(pattern: "MM/DD").dateFormat, "MM/dd")
    }

    func testQuotedTokensAreRewrittenToo() {
        // KNOWN QUIRK: the YYYY→yyyy rewrite is a blind string replace, so a
        // quoted literal 'YYYY' (meant to print as-is) also becomes 'yyyy'.
        // Documenting current behavior; fix would require quote-aware scanning.
        XCTAssertEqual(
            DateFormatter.statusDateFormatter(pattern: "'YYYY' yyyy").dateFormat,
            "'yyyy' yyyy"
        )
    }

    func testCachesFormatterPerPattern() {
        let first = DateFormatter.statusDateFormatter(pattern: "HH:mm")
        let second = DateFormatter.statusDateFormatter(pattern: "HH:mm")
        XCTAssertTrue(first === second)
        XCTAssertFalse(first === DateFormatter.statusDateFormatter(pattern: "HH:mm:ss"))
    }
}
