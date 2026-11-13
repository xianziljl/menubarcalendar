import XCTest
@testable import MenuBarCalendar

final class FestivalModelTests: XCTestCase {
    private let calendar = Calendar.current

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // FestivalModel.info(for:) reads the app's preferred localization, which in
    // the test runner is English. Branch on L10n.isChinese so the assertions
    // stay valid regardless of where the tests run.

    func testInternationalHolidayOnNewYearsDay() {
        let info = FestivalModel.info(for: makeDate(2026, 1, 1))
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.kind, .festival)
        if L10n.isChinese {
            XCTAssertEqual(info?.text, "元旦")
        } else {
            XCTAssertEqual(info?.text, "New Year's Day")
        }
    }

    func testInternationalHolidayOnChristmas() {
        let info = FestivalModel.info(for: makeDate(2026, 12, 25))
        XCTAssertNotNil(info)
        if L10n.isChinese {
            XCTAssertEqual(info?.text, "圣诞节")
        } else {
            XCTAssertEqual(info?.text, "Christmas")
        }
    }

    func testChineseOnlyFestivalsAreHiddenForNonChineseLocale() {
        // 国庆节 (10/1) is Chinese-locale only; English locale gets nil.
        let info = FestivalModel.info(for: makeDate(2026, 10, 1))
        if L10n.isChinese {
            XCTAssertEqual(info?.text, "国庆节")
        } else {
            XCTAssertNil(info)
        }
    }

    func testSolarTermQingming2026() {
        // 清明 2026 falls on April 5 (C-value formula, verified against the
        // official calendar for this year).
        let info = FestivalModel.info(for: makeDate(2026, 4, 5))
        if L10n.isChinese {
            XCTAssertEqual(info?.text, "清明")
            XCTAssertEqual(info?.kind, .solarTerm)
        } else {
            XCTAssertNil(info)
        }
    }

    func testPlainDayHasNoFestival() {
        let info = FestivalModel.info(for: makeDate(2026, 3, 15))
        XCTAssertNil(info)
    }
}
