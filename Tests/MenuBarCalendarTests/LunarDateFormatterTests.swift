import XCTest
@testable import MenuBarCalendar

final class LunarDateFormatterTests: XCTestCase {
    func testDayTextCoversAllLunarDayNames() {
        XCTAssertEqual(LunarDateFormatter.dayText(for: 1), "初一")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 2), "初二")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 9), "初九")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 10), "初十")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 11), "十一")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 14), "十四")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 19), "十九")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 20), "二十")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 21), "廿一")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 25), "廿五")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 29), "廿九")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 30), "三十")
    }

    func testDayTextFallsBackToNumberForOutOfRangeDays() {
        XCTAssertEqual(LunarDateFormatter.dayText(for: 0), "0")
        XCTAssertEqual(LunarDateFormatter.dayText(for: 31), "31")
    }
}
