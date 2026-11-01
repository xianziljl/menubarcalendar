import Foundation

enum FestivalKind {
    case festival
    case solarTerm
}

struct FestivalInfo: Equatable {
    let text: String
    let kind: FestivalKind

    static func == (lhs: FestivalInfo, rhs: FestivalInfo) -> Bool {
        lhs.text == rhs.text
    }
}

enum FestivalModel {

    // MARK: - International Holidays (fixed solar dates, all locales)

    private static let internationalHolidays: [String: (zh: String, en: String)] = [
        "1/1": ("元旦", "New Year's Day"),
        "2/14": ("情人节", "Valentine's Day"),
        "3/8": ("妇女节", "Women's Day"),
        "4/1": ("愚人节", "April Fool's Day"),
        "5/1": ("劳动节", "Labour Day"),
        "6/1": ("儿童节", "Children's Day"),
        "10/31": ("万圣节", "Halloween"),
        "12/24": ("平安夜", "Christmas Eve"),
        "12/25": ("圣诞节", "Christmas"),
        "12/31": ("跨年夜", "New Year's Eve"),
    ]

    // MARK: - Lunar Festivals (fixed lunar month/day)

    private static let lunarFestivals: [String: (zh: String, en: String)] = [
        "1/1": ("春节", "Spring Festival"),
        "1/5": ("破五节", "Breaking the Five"),
        "1/15": ("元宵节", "Lantern Festival"),
        "2/2": ("龙抬头", "Dragon Head Raising Day"),
        "3/3": ("上巳节", "Shangsi Festival"),
        "5/5": ("端午节", "Dragon Boat Festival"),
        "6/6": ("天贶节", "Tiankuang Festival"),
        "7/7": ("七夕节", "Qixi Festival"),
        "7/15": ("中元节", "Zhongyuan Festival"),
        "8/15": ("中秋节", "Mid-Autumn Festival"),
        "9/9": ("重阳节", "Double Ninth Festival"),
        "10/1": ("寒衣节", "Winter Clothing Festival"),
        "10/15": ("下元节", "Xiayuan Festival"),
        "12/8": ("腊八节", "Laba Festival"),
        "12/23": ("小年", "Little New Year"),
    ]

    // MARK: - Fixed Solar Festivals (Chinese public holidays, Chinese locale only)

    private static let solarFestivals: [String: String] = [
        "10/1": "国庆节",
    ]

    // MARK: - 24 Solar Terms (Chinese locale only)

    private struct SolarTermData {
        let name: String
        let month: Int
        let constant: Double
    }

    private static let solarTermConstants: [SolarTermData] = [
        SolarTermData(name: "小寒", month: 1, constant: 5.4055),
        SolarTermData(name: "大寒", month: 1, constant: 20.12),
        SolarTermData(name: "立春", month: 2, constant: 3.87),
        SolarTermData(name: "雨水", month: 2, constant: 18.73),
        SolarTermData(name: "惊蛰", month: 3, constant: 5.63),
        SolarTermData(name: "春分", month: 3, constant: 20.646),
        SolarTermData(name: "清明", month: 4, constant: 4.81),
        SolarTermData(name: "谷雨", month: 4, constant: 20.1),
        SolarTermData(name: "立夏", month: 5, constant: 5.52),
        SolarTermData(name: "小满", month: 5, constant: 21.04),
        SolarTermData(name: "芒种", month: 6, constant: 5.678),
        SolarTermData(name: "夏至", month: 6, constant: 21.37),
        SolarTermData(name: "小暑", month: 7, constant: 7.108),
        SolarTermData(name: "大暑", month: 7, constant: 22.83),
        SolarTermData(name: "立秋", month: 8, constant: 7.5),
        SolarTermData(name: "处暑", month: 8, constant: 23.13),
        SolarTermData(name: "白露", month: 9, constant: 7.646),
        SolarTermData(name: "秋分", month: 9, constant: 23.042),
        SolarTermData(name: "寒露", month: 10, constant: 8.318),
        SolarTermData(name: "霜降", month: 10, constant: 23.438),
        SolarTermData(name: "立冬", month: 11, constant: 7.438),
        SolarTermData(name: "小雪", month: 11, constant: 22.36),
        SolarTermData(name: "大雪", month: 12, constant: 7.18),
        SolarTermData(name: "冬至", month: 12, constant: 21.94),
    ]

    // MARK: - Public API

    /// Returns festival/solar-term info for the given date, or nil.
    /// Priority: international > Chinese solar > lunar festival > solar term.
    /// Non-Chinese locale: international holidays only.
    static func info(for date: Date) -> FestivalInfo? {
        let isChinese = L10n.isChinese

        // 1. International holidays (all locales, highest priority)
        if let holiday = internationalHoliday(for: date) {
            return FestivalInfo(
                text: isChinese ? holiday.zh : holiday.en,
                kind: .festival
            )
        }

        // Non-Chinese locale: international holidays only
        guard isChinese else { return nil }

        // 2. Chinese solar holidays
        if let festival = solarFestival(for: date) {
            return FestivalInfo(text: festival, kind: .festival)
        }

        // 3. Lunar traditional festivals
        if let festival = lunarFestival(for: date) {
            return FestivalInfo(text: festival.zh, kind: .festival)
        }

        // 4. Solar terms
        if let term = solarTerm(for: date) {
            return FestivalInfo(text: term, kind: .solarTerm)
        }

        return nil
    }

    // MARK: - Lunar Festival Lookup

    private static func lunarFestival(
        for date: Date
    ) -> (zh: String, en: String)? {
        let chineseCalendar = Calendar(identifier: .chinese)
        let components = chineseCalendar.dateComponents([.month, .day], from: date)
        let month = components.month ?? 0
        let day = components.day ?? 0
        let key = "\(month)/\(day)"

        if let festival = lunarFestivals[key] {
            return festival
        }

        // Check for 除夕 (New Year's Eve): last day of lunar year 12
        if month == 12 {
            if let nextDate = chineseCalendar.date(byAdding: .day, value: 1, to: date) {
                let nextComponents = chineseCalendar.dateComponents(
                    [.month, .day], from: nextDate
                )
                if nextComponents.month == 1, nextComponents.day == 1 {
                    return ("除夕", "Chinese New Year's Eve")
                }
            }
        }

        return nil
    }

    // MARK: - Solar Festival Lookup

    private static func internationalHoliday(
        for date: Date
    ) -> (zh: String, en: String)? {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return internationalHolidays["\(month)/\(day)"]
    }

    private static func solarFestival(for date: Date) -> String? {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return solarFestivals["\(month)/\(day)"]
    }

    // MARK: - Solar Term Lookup

    private static func solarTerm(for date: Date) -> String? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)

        for term in solarTermConstants where term.month == month {
            let termDay = solarTermDay(year: year, term: term)
            if day == termDay {
                return term.name
            }
        }
        return nil
    }

    /// Approximate solar term day using the standard C-value formula.
    /// Valid for years 2000-2099.
    private static func solarTermDay(year: Int, term: SolarTermData) -> Int {
        let y = year % 100
        let base = Int(floor(Double(y) * 0.2422 + term.constant))
        if term.month <= 6 {
            return base - (y - 1) / 4
        } else {
            return base - y / 4
        }
    }
}
