import SwiftUI

struct CalendarGridView: View {
    let month: Date
    @Binding var selectedDate: Date
    let firstWeekday: Int
    let showLunar: Bool
    let showHolidayBadges: Bool
    let eventDots: [Date: [Color]]
    let holidayInfo: [Date: HolidayInfo]
    let showsAdjacentMonthDates: Bool

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let cellDate = date(forRow: row, column: column)

                        if showsAdjacentMonthDates
                            || calendar.isDate(cellDate, equalTo: month, toGranularity: .month) {
                            CalendarCellView(
                                date: cellDate,
                                month: month,
                                selectedDate: selectedDate,
                                showLunar: showLunar,
                                showHolidayBadges: showHolidayBadges,
                                dotColors: eventDots[calendar.startOfDay(for: cellDate)] ?? [],
                                holidayInfo: holidayInfo[calendar.startOfDay(for: cellDate)]
                            ) {
                                selectedDate = cellDate
                            }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: showLunar ? 34 : 28)
                                .padding(.horizontal, 1)
                                .padding(.vertical, 1)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func date(forRow row: Int, column: Int) -> Date {
        guard let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return month
        }

        let weekday = calendar.component(.weekday, from: firstDay)
        let leadingEmptyDays = (weekday - firstWeekday + 7) % 7
        let dayOffset = row * 7 + column - leadingEmptyDays
        return calendar.date(byAdding: .day, value: dayOffset, to: firstDay) ?? firstDay
    }

    private var rowCount: Int {
        guard showsAdjacentMonthDates else {
            let firstDay = calendar.date(
                from: calendar.dateComponents([.year, .month], from: month)
            ) ?? month
            let daysInMonth = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? 30
            let firstDayWeekday = calendar.component(.weekday, from: firstDay)
            let leadingEmptyDays = (firstDayWeekday - firstWeekday + 7) % 7
            return Int(ceil(Double(daysInMonth + leadingEmptyDays) / 7.0))
        }

        return 6
    }
}

struct CalendarCellView: View {
    let date: Date
    let month: Date
    let selectedDate: Date
    let showLunar: Bool
    let showHolidayBadges: Bool
    let dotColors: [Color]
    let holidayInfo: HolidayInfo?
    let selectDate: () -> Void

    private var accentColor: Color {
        Color(nsColor: .controlAccentColor)
    }

    private var todayTextColor: Color {
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        let red = accent?.redComponent ?? 0.2
        let green = accent?.greenComponent ?? 0.45
        let blue = accent?.blueComponent ?? 0.9
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

        return luminance > 0.62 ? .black : .white
    }

    private let calendar = Calendar.current

    var body: some View {
        Button(action: selectDate) {
            VStack(spacing: 1) {
                Text(dayNumber)
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? todayTextColor : dayTextColor)
                    .overlay(alignment: .topTrailing) {
                        if let badgeText = holidayBadgeText {
                            Text(badgeText)
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(holidayBadgeColor)
                                .fixedSize()
                                .offset(x: 8, y: -5)
                        }
                    }

                if showLunar {
                    Text(lunarDay)
                        .font(.system(size: 8))
                        .foregroundStyle(isSelected ? todayTextColor.opacity(0.86) : lunarTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                HStack(spacing: 2) {
                    ForEach(dotColors.indices, id: \.self) { index in
                        Circle()
                            .fill(dotColors[index])
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: showLunar ? 34 : 28)
            .background(highlight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(holidayHelpText ?? "")
        .padding(.horizontal, 1)
        .padding(.vertical, 1)
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(date, equalTo: month, toGranularity: .month)
    }

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    private var isSelected: Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private var isSelectedMonth: Bool {
        calendar.isDate(selectedDate, equalTo: month, toGranularity: .month)
    }

    private var isWeekend: Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    private var dayNumber: String {
        String(calendar.component(.day, from: date))
    }

    private var holidayBadgeText: String? {
        guard showHolidayBadges, let holidayInfo else { return nil }
        return holidayInfo.kind == .holiday ? "休" : "班"
    }

    private var holidayBadgeColor: Color {
        holidayInfo?.kind == .work ? Color(nsColor: .systemRed) : Color(nsColor: .systemGreen)
    }

    private var holidayHelpText: String? {
        guard let holidayInfo else { return nil }
        let actionText = holidayInfo.kind == .holiday ? "休" : "班"
        return "\(holidayInfo.name) · \(actionText)"
    }

    private var lunarDay: String {
        LunarDateFormatter.cellText(for: date)
    }

    private var dayTextColor: Color {
        if isSelected {
            return Color.primary
        }

        if isToday {
            return .white
        }

        if !isCurrentMonth {
            return Color.primary.opacity(0.32)
        }

        if !isSelectedMonth {
            return isWeekend ? Color.primary.opacity(0.52) : Color.primary.opacity(0.68)
        }

        return Color.primary
    }

    private var lunarTextColor: Color {
        if isToday {
            return .white.opacity(0.86)
        }

        if !isCurrentMonth {
            return Color.primary.opacity(0.25)
        }

        if !isSelectedMonth {
            return isWeekend ? Color.primary.opacity(0.38) : Color.primary.opacity(0.5)
        }

        return isWeekend ? Color.primary.opacity(0.46) : Color.primary.opacity(0.66)
    }

    private var highlightDiameter: CGFloat {
        showLunar ? 37 : 30
    }

    @ViewBuilder
    private var highlight: some View {
        if isSelected {
            Circle()
                .fill(accentColor)
                .frame(width: highlightDiameter, height: highlightDiameter)
        } else if isToday {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    Circle()
                        .strokeBorder(accentColor, lineWidth: 1.5)
                )
                .frame(width: highlightDiameter, height: highlightDiameter)
        }
    }
}
