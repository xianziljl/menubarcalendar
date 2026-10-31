import Foundation

enum LunarDateFormatter {
    private static let monthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
    private static let dayNames = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

    static func monthAndDayText(for date: Date) -> String {
        let chineseCalendar = Calendar(identifier: .chinese)
        let components = chineseCalendar.dateComponents([.month, .day], from: date)

        if !L10n.isChinese {
            let monthIndex = components.month ?? 1
            let isLeapMonth = components.isLeapMonth ?? false
            let leapText = isLeapMonth ? "leap " : ""
            return "Lunar \(leapText)\(monthIndex)/\(components.day ?? 1)"
        }

        let yearFormatter = DateFormatter()
        yearFormatter.calendar = chineseCalendar
        yearFormatter.locale = Locale(identifier: "zh_CN")
        yearFormatter.dateFormat = "U年"

        let monthText = monthText(for: components)
        let dayText = dayText(for: components.day ?? 1)

        return yearFormatter.string(from: date) + " " + monthText + dayText
    }

    static func dayText(for date: Date) -> String {
        let chineseCalendar = Calendar(identifier: .chinese)
        let day = chineseCalendar.component(.day, from: date)

        if L10n.isChinese {
            return dayText(for: day)
        }

        return String(day)
    }

    static func cellText(for date: Date) -> String {
        let chineseCalendar = Calendar(identifier: .chinese)
        let components = chineseCalendar.dateComponents([.month, .day], from: date)
        let day = components.day ?? 1

        guard day == 1 else {
            return dayText(for: date)
        }

        if L10n.isChinese {
            return monthText(for: components)
        }

        return "L\(components.month ?? 1)"
    }

    private static func monthText(
        for components: DateComponents
    ) -> String {
        let monthIndex = (components.month ?? 1) - 1
        let isLeapMonth = components.isLeapMonth ?? false
        let monthName = monthNames[max(0, min(11, monthIndex))]
        return (isLeapMonth ? "闰" : "") + monthName + "月"
    }

    static func dayText(for day: Int) -> String {
        switch day {
        case 1...10:
            return "初" + dayNames[day - 1]
        case 11...19:
            return "十" + dayNames[day - 11]
        case 20:
            return "二十"
        case 21...29:
            return "廿" + dayNames[day - 21]
        case 30:
            return "三十"
        default:
            return String(day)
        }
    }
}
