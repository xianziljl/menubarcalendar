import XCTest
@testable import MenuBarCalendar

final class DateFormatterTests: XCTestCase {
    func testNormalizesWeekBasedYearAndDayOfYearTokens() {
        // YYYY/DD cause off-by-one dates around year boundaries; the app
        // rewrites them to calendar-year/day-of-month on purpose.
        XCTAssertEqual(DateFormatter.statusDateFormatter(pattern: "YYYY-MM-dd").dateFormat, "yyyy-MM-dd")
        XCTAssertEqual(DateFormatter.statusDateFormatter(pattern: "MM/DD").dateFormat, "MM/dd")
    }

    func testKeepsQuotedTokensLiteral() {
        // Quoted text is literal output, not a token — it must survive the
        // rewrite untouched.
        XCTAssertEqual(
            DateFormatter.statusDateFormatter(pattern: "'YYYY' yyyy").dateFormat,
            "'YYYY' yyyy"
        )
        XCTAssertEqual(
            DateFormatter.statusDateFormatter(pattern: "MM 'DD' dd").dateFormat,
            "MM 'DD' dd"
        )
    }

    func testCachesFormatterPerPattern() {
        let first = DateFormatter.statusDateFormatter(pattern: "HH:mm")
        let second = DateFormatter.statusDateFormatter(pattern: "HH:mm")
        XCTAssertTrue(first === second)
        XCTAssertFalse(first === DateFormatter.statusDateFormatter(pattern: "HH:mm:ss"))
    }
}
