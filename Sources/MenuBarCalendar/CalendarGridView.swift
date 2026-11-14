import SwiftUI

struct CalendarGridView: View {
    let month: Date
    @Binding var selectedDate: Date
    let firstWeekday: Int
    let showLunar: Bool
    let showHolidayBadges: Bool
    let showFestivals: Bool
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
                                showFestivals: showFestivals,
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
    let showFestivals: Bool
    let dotColors: [Color]
    let holidayInfo: HolidayInfo?
    let selectDate: () -> Void

    @State private var isHovered = false

    // Tiny fonts keep their exact default size but scale with the user's
    // system text-size setting via @ScaledMetric.
    @ScaledMetric(relativeTo: .caption2) private var lunarFontSize: CGFloat = 8
    @ScaledMetric(relativeTo: .caption2) private var badgeFontSize: CGFloat = 7

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
                    .font(.system(.body).weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? todayTextColor : dayTextColor)
                    .overlay(alignment: .topTrailing) {
                        if let badgeText = holidayBadgeText {
                            Text(badgeText)
                                .font(.system(size: badgeFontSize, weight: .heavy))
                                .foregroundStyle(holidayBadgeColor)
                                .fixedSize()
                                .offset(x: 8, y: -5)
                        }
                    }

                if showLunar {
                    Text(lunarDay)
                        .font(.system(size: lunarFontSize))
                        .foregroundStyle(lunarDayColor)
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
        .onHover { hovering in
            isHovered = hovering
        }
        .help(holidayHelpText ?? "")
        // VoiceOver reads the full context (date, lunar, festival, holiday,
        // event count) instead of just the day number.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cellAccessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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

    private var cellAccessibilityDescription: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none

        var parts = [formatter.string(from: date)]

        if isToday {
            parts.append(L10n.text("Today"))
        }
        if showFestivals, let info = FestivalModel.info(for: date) {
            parts.append(info.text)
        }
        if showLunar {
            parts.append(LunarDateFormatter.dayText(for: date))
        }
        if let holidayHelpText, !holidayHelpText.isEmpty {
            parts.append(holidayHelpText)
        }
        if !dotColors.isEmpty {
            parts.append(String(format: L10n.text("%d events"), dotColors.count))
        }

        return parts.joined(separator: ", ")
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
        if showFestivals, let info = FestivalModel.info(for: date) {
            return info.text
        }
        return LunarDateFormatter.cellText(for: date)
    }

    private var specialDayInfo: FestivalInfo? {
        guard showFestivals else { return nil }
        return FestivalModel.info(for: date)
    }

    private var festivalColor: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(red: 1.0, green: 0.62, blue: 0.26, alpha: 1.0)
                : NSColor(red: 0.85, green: 0.42, blue: 0.0, alpha: 1.0)
        }))
    }

    private var solarTermColor: Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(red: 0.58, green: 0.64, blue: 0.95, alpha: 1.0)
                : NSColor(red: 0.28, green: 0.28, blue: 0.65, alpha: 1.0)
        }))
    }

    private var lunarDayColor: Color {
        if isToday || isSelected {
            return .white.opacity(0.86)
        }
        if let info = specialDayInfo {
            let base = info.kind == .festival ? festivalColor : solarTermColor
            if !isCurrentMonth {
                return base.opacity(0.3)
            }
            return base
        }
        return lunarTextColor
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
                .fill(Color.primary.opacity(isHovered ? 0.16 : 0.08))
                .overlay(
                    Circle()
                        .strokeBorder(accentColor, lineWidth: 1.5)
                )
                .frame(width: highlightDiameter, height: highlightDiameter)
        } else if isHovered {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: highlightDiameter, height: highlightDiameter)
        }
    }
}
