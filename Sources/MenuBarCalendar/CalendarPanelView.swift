import SwiftUI
import AppKit
import EventKit

struct CalendarPanelView: View {
    @AppStorage("showLunar")
    private var showLunar = L10n.isChinese

    @AppStorage("showHolidayBadges")
    private var showHolidayBadges = L10n.isChinese

    @AppStorage("showFestivals")
    private var showFestivals = L10n.isChinese

    @AppStorage("firstWeekday")
    private var firstWeekday = 1

    @AppStorage("monthDisplayMode")
    private var monthDisplayModeRaw = MonthDisplayMode.single.rawValue

    @AppStorage("dualMonthLayout")
    private var dualMonthLayoutRaw = DualMonthLayout.horizontal.rawValue

    @AppStorage("showYearSwitchButtons")
    private var showYearSwitchButtons = false

    @AppStorage("showEventStatus")
    private var showEventStatus = true

    @AppStorage("showEventDuration")
    private var showEventDuration = true

    @StateObject private var eventsModel = CalendarEventsModel()
    @StateObject private var holidayModel = HolidayModel()
    @State private var displayedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var selectedDate = Date()
    @State private var showsNewEventPopover = false
    @State private var selectedDetailEventID: String?
    @State private var eventPresentationID = UUID()

    private let calendar = Calendar.current
    private let singlePanelWidth: CGFloat = 284
    private let dualMonthSpacing: CGFloat = 16
    private let dualMonthWidth: CGFloat = 232

    private var monthDisplayMode: MonthDisplayMode {
        MonthDisplayMode(rawValue: monthDisplayModeRaw) ?? .single
    }

    private var dualMonthLayout: DualMonthLayout {
        DualMonthLayout(rawValue: dualMonthLayoutRaw) ?? .horizontal
    }

    private var isSelectedDateToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: Date())
    }

    private var isCompactHeader: Bool {
        showYearSwitchButtons && !(monthDisplayMode == .dual && dualMonthLayout == .horizontal)
    }

    private var panelWidth: CGFloat {
        if monthDisplayMode == .dual && dualMonthLayout == .horizontal {
            return dualMonthWidth * 2 + dualMonthSpacing + 28
        }
        return singlePanelWidth
    }

    private var calendarContentWidth: CGFloat {
        panelWidth - 28
    }

    private var monthCount: Int {
        monthDisplayMode == .dual ? 2 : 1
    }

    private var headerButtonWidth: CGFloat {
        isCompactHeader ? 18 : 22
    }

    private var headerButtonHeight: CGFloat {
        isCompactHeader ? 18 : 22
    }

    private var headerButtonSpacing: CGFloat {
        isCompactHeader ? 0 : 1
    }

    private var headerGroupSpacing: CGFloat {
        isCompactHeader ? 2 : 5
    }

    private var optionsMenuWidth: CGFloat {
        isCompactHeader ? 18 : 22
    }

    private var optionsMenuHeight: CGFloat {
        isCompactHeader ? 18 : 22
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            weekHeader
            monthGrid
            Divider()
            eventSection
        }
        .padding(14)
        .frame(width: panelWidth)
        .background(PanelWindowIdentifierAccessor())
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == Self.panelWindowIdentifier else {
                return
            }

            eventPresentationID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.identifier == Self.panelWindowIdentifier else {
                return
            }

            closeTransientPopovers()
        }
        .task {
            selectedDate = Date()
            displayedMonth = monthStart(for: Date())
            await eventsModel.requestAccessIfNeeded()
            await eventsModel.load(
                for: selectedDate,
                displayedMonth: displayedMonth,
                monthCount: monthCount
            )
            await holidayModel.refreshIfNeeded(for: Date())
        }
        .onChange(of: selectedDate) { newValue in
            let targetMonth = monthStart(for: newValue)
            let isWithinDisplayedRange = isDate(
                newValue,
                inDisplayedMonthsFrom: displayedMonth
            )

            if !isWithinDisplayedRange {
                displayedMonth = targetMonth
            }

            Task {
                await eventsModel.load(
                    for: newValue,
                    displayedMonth: displayedMonth,
                    monthCount: monthCount
                )
            }
        }
        .onChange(of: monthDisplayModeRaw) { _ in
            reloadEvents()
        }
        .onChange(of: dualMonthLayoutRaw) { _ in
            reloadEvents()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(monthTitle)
                .font(.system(size: isCompactHeader ? 13 : 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: headerGroupSpacing) {
                if showYearSwitchButtons {
                    Button {
                        moveYear(-1)
                    } label: {
                        Image(systemName: "chevron.left.2")
                            .font(.system(size: isCompactHeader ? 10 : 12, weight: .semibold))
                            .frame(width: headerButtonWidth, height: headerButtonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .help(L10n.text("Previous Year"))
                }

                HStack(spacing: headerButtonSpacing) {
                    Button {
                        moveMonth(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: isCompactHeader ? 10 : showYearSwitchButtons ? 12 : 13, weight: .semibold))
                            .frame(width: headerButtonWidth, height: headerButtonHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .help(L10n.text("Previous Month"))

                    Button {
                        showToday()
                    } label: {
                        Image(systemName: "smallcircle.filled.circle")
                            .font(.system(size: isCompactHeader ? 10 : showYearSwitchButtons ? 12 : 13, weight: .semibold))
                            .frame(width: headerButtonWidth, height: headerButtonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .help(L10n.text("Today"))

                    Button {
                        moveMonth(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: isCompactHeader ? 10 : showYearSwitchButtons ? 12 : 13, weight: .semibold))
                            .frame(width: headerButtonWidth, height: headerButtonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .help(L10n.text("Next Month"))
                }

                if showYearSwitchButtons {
                    Button {
                        moveYear(1)
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: isCompactHeader ? 10 : 12, weight: .semibold))
                            .frame(width: headerButtonWidth, height: headerButtonHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight()
                    .help(L10n.text("Next Year"))
                }

                optionsMenu
                    .padding(.leading, showYearSwitchButtons ? 6 : 0)
                    .frame(width: optionsMenuWidth, height: optionsMenuHeight)
                    .fixedSize()
                    .layoutPriority(2)
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Toggle(L10n.text("Dual Month Display"), isOn: dualMonthDisplayBinding)

            Toggle(L10n.text("Show lunar"), isOn: $showLunar)

            if L10n.isChinese {
                Toggle(L10n.text("Show festivals and solar terms"), isOn: $showFestivals)
            }

            Divider()

            Button {
                CalendarOpener.openCalendarApp()
            } label: {
                Label(L10n.text("Open Calendar App"), systemImage: "calendar")
            }

            Button {
                openSettings()
            } label: {
                Label(L10n.text("Settings"), systemImage: "gearshape")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(L10n.text("Quit"), systemImage: "power")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: isCompactHeader ? 10 : showYearSwitchButtons ? 12 : 13, weight: .semibold))
                    .foregroundStyle(.primary)
                .frame(width: optionsMenuWidth, height: optionsMenuHeight)
                .contentShape(Rectangle())
                .hoverHighlight()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(L10n.text("More"))
    }

    private var dualMonthDisplayBinding: Binding<Bool> {
        Binding(
            get: { monthDisplayMode == .dual },
            set: { isEnabled in
                monthDisplayModeRaw = isEnabled
                    ? MonthDisplayMode.dual.rawValue
                    : MonthDisplayMode.single.rawValue
            }
        )
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = L10n.isChinese ? "yyyy年M月" : "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }

    private var weekHeader: some View {
        Group {
            if monthCount == 2 && dualMonthLayout == .horizontal {
                HStack(spacing: dualMonthSpacing) {
                    weekdayHeader
                    weekdayHeader
                }
                .frame(width: calendarContentWidth)
            } else {
                weekdayHeader
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdays, id: \.weekday) { weekday in
                Text(weekday.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(weekday.isWeekend ? Color.primary.opacity(0.38) : Color.primary.opacity(0.72))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        CalendarPagerView(
            month: displayedMonth,
            selectedDate: $selectedDate,
            firstWeekday: firstWeekday,
            showLunar: showLunar,
            showHolidayBadges: showHolidayBadges,
            showFestivals: effectiveShowFestivals,
            eventDots: eventsModel.eventDots,
            holidayInfo: holidayModel.holidayInfo,
            width: calendarContentWidth,
            monthCount: monthCount,
            isVerticalDualLayout: dualMonthLayout == .vertical,
            dualMonthSpacing: dualMonthSpacing,
            onSwipe: moveMonth
        )
    }

    private var effectiveShowFestivals: Bool {
        if !L10n.isChinese { return true }
        return showFestivals
    }

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    eventTitle

                    if showLunar {
                        Text(selectedDateSubtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                Button {
                    showsNewEventPopover = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 6)
                .help(L10n.text("Add Event"))
            }
            .popover(
                isPresented: $showsNewEventPopover,
                arrowEdge: .trailing
            ) {
                NewEventPopoverView(
                    selectedDate: selectedDate,
                    eventsModel: eventsModel,
                    onCreated: {
                        showsNewEventPopover = false
                    }
                )
            }

            if !eventsModel.hasAccess {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        eventsModel.isDenied
                            ? L10n.text("Calendar access was denied.")
                            : L10n.text("Calendar access has not been granted.")
                    )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if eventsModel.isDenied {
                        Button(L10n.text("Open Calendar Permissions")) {
                            CalendarOpener.openPermissionSettings()
                        }
                        .controlSize(.small)
                    } else {
                        Button(L10n.text("Request Calendar Access")) {
                            Task {
                                await eventsModel.requestAccess()
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else if eventsModel.items.isEmpty {
                Text(L10n.text("No events for this day."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    LazyVGrid(
                        columns: eventListColumns,
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ForEach(eventsModel.items) { event in
                            EventRowView(
                                event: event,
                                eventsModel: eventsModel,
                                currentDate: context.date,
                                showsDetails: selectedDetailEventID == event.id,
                                changeShowsDetails: { shows in
                                    if shows {
                                        selectedDetailEventID = event.id
                                    } else if selectedDetailEventID == event.id {
                                        selectedDetailEventID = nil
                                    }
                                }
                            )
                                .id("\(event.id)-\(eventPresentationID)")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventListColumns: [GridItem] {
        let isHorizontalDualMonth = monthDisplayMode == .dual
            && dualMonthLayout == .horizontal

        if isHorizontalDualMonth {
            return [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible())
            ]
        }

        return [GridItem(.flexible())]
    }

    private var selectedDateSubtitle: String {
        let lunarText = LunarDateFormatter.monthAndDayText(for: selectedDate)
        guard effectiveShowFestivals, let info = FestivalModel.info(for: selectedDate) else {
            return lunarText
        }
        return "\(info.text) · \(lunarText)"
    }

    private var eventTitle: some View {
        HStack(spacing: 0) {
            if isSelectedDateToday {
                Text("\(L10n.text("Today")) ")
                    .foregroundStyle(Color.accentColor)
            }

            Text(dayTitle)
                .foregroundStyle(Color.primary)
        }
        .font(.system(size: 12.5, weight: .semibold))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        let dateText = formatter.string(from: selectedDate)
        // Week boundaries must follow the user's "week starts on" setting so
        // the label matches the grid rows, not the system calendar.
        var weekCalendar = calendar
        weekCalendar.firstWeekday = firstWeekday
        let weekNumber = weekCalendar.component(.weekOfYear, from: selectedDate)
        let weekText = String(format: L10n.text("Week %d"), weekNumber)
        return "\(dateText) · \(weekText)"
    }

    private var weekdays: [WeekdayItem] {
        var result: [WeekdayItem] = []
        for offset in 0..<7 {
            let weekday = ((firstWeekday - 1 + offset) % 7) + 1
            let symbol = calendar.shortStandaloneWeekdaySymbols[weekday - 1]
            result.append(WeekdayItem(weekday: weekday, symbol: symbol, isWeekend: weekday == 1 || weekday == 7))
        }
        return result
    }

    private func moveMonth(_ offset: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }

        let normalizedNewMonth = monthStart(for: newMonth)
        let keepsSelectedMonth = isDate(
            selectedDate,
            inDisplayedMonthsFrom: normalizedNewMonth
        )

        displayedMonth = normalizedNewMonth
        if !keepsSelectedMonth {
            selectedDate = preferredDate(in: normalizedNewMonth)
        }
    }

    private func moveYear(_ offset: Int) {
        guard let newMonth = calendar.date(byAdding: .year, value: offset, to: displayedMonth) else { return }

        let normalizedNewMonth = monthStart(for: newMonth)
        displayedMonth = normalizedNewMonth
        selectedDate = preferredDate(in: normalizedNewMonth)
    }

    private func preferredDate(in month: Date) -> Date {
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        let preferredDay = min(calendar.component(.day, from: selectedDate), dayCount)
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = preferredDay
        return calendar.date(from: components) ?? month
    }

    private func openSettings() {
        SettingsWindowManager.shared.show()
    }

    private func showToday() {
        let today = Date()
        let todayMonth = monthStart(for: today)
        let isViewingTodayMonth = calendar.isDate(
            displayedMonth,
            equalTo: todayMonth,
            toGranularity: .month
        )

        if !calendar.isDate(selectedDate, inSameDayAs: today) {
            selectedDate = today
        }

        if !isViewingTodayMonth {
            displayedMonth = todayMonth
        }

        Task {
            await eventsModel.load(
                for: today,
                displayedMonth: todayMonth,
                monthCount: monthCount
            )
        }
    }

    private func reloadEvents() {
        Task {
            await eventsModel.load(
                for: selectedDate,
                displayedMonth: displayedMonth,
                monthCount: monthCount
            )
        }
    }

    /// SwiftUI popover state can outlive a hidden MenuBarExtra window. Closing
    /// the identified popover windows while the main panel is still closing
    /// keeps the transient popover from appearing on the next panel open.
    private func closeTransientPopovers() {
        showsNewEventPopover = false
        selectedDetailEventID = nil
        eventPresentationID = UUID()

        let popoverIdentifiers: Set<NSUserInterfaceItemIdentifier> = [
            EventDetailPopoverView.popoverWindowIdentifier,
            NewEventPopoverView.popoverWindowIdentifier
        ]

        for window in NSApp.windows {
            guard window.isVisible,
                  let identifier = window.identifier,
                  popoverIdentifiers.contains(identifier) else {
                continue
            }

            window.close()
        }
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func isDate(
        _ date: Date,
        inDisplayedMonthsFrom startMonth: Date
    ) -> Bool {
        for offset in 0..<monthCount {
            guard let month = calendar.date(
                byAdding: .month,
                value: offset,
                to: startMonth
            ) else { continue }

            if calendar.isDate(date, equalTo: month, toGranularity: .month) {
                return true
            }
        }
        return false
    }
}

private extension CalendarPanelView {
    static let panelWindowIdentifier = NSUserInterfaceItemIdentifier("MenuBarCalendarPanel")
}

private struct PanelWindowIdentifierAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        PanelIdentifierView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PanelIdentifierView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = CalendarPanelView.panelWindowIdentifier
        }
    }
}

private struct WeekdayItem {
    let weekday: Int
    let symbol: String
    let isWeekend: Bool
}

private struct HoverHighlightModifier: ViewModifier {
    var cornerRadius: CGFloat = 5

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private extension View {
    func hoverHighlight(cornerRadius: CGFloat = 5) -> some View {
        modifier(HoverHighlightModifier(cornerRadius: cornerRadius))
    }
}

private struct EventRowView: View {
    let event: CalendarEventItem
    let eventsModel: CalendarEventsModel
    let currentDate: Date
    let showsDetails: Bool
    let changeShowsDetails: (Bool) -> Void

    @AppStorage("showEventStatus")
    private var showEventStatus = true

    @AppStorage("showEventDuration")
    private var showEventDuration = true

    @State private var isHovered = false

    var body: some View {
        Button {
            changeShowsDetails(true)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(event.color)
                    .frame(width: 3, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(timeText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if showEventStatus, let status = statusText {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(status)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isInProgress ? Color.green : Color.primary)
                            .monospacedDigit()
                            .lineLimit(1)

                        if isInProgress {
                            Text(endsInText)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.primary.opacity(0.55))
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
            }
            .opacity(isExpired ? 0.45 : 1)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered || showsDetails ? 0.08 : 0))
                    .padding(.horizontal, -5)
                    .padding(.vertical, -2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(RoundedRectangle(cornerRadius: 6).inset(by: -2))
        .popover(
            isPresented: Binding(
                get: { showsDetails },
                set: { changeShowsDetails($0) }
            ),
            arrowEdge: .trailing
        ) {
            EventDetailPopoverView(
                event: event,
                eventsModel: eventsModel,
                onDeleted: {
                    changeShowsDetails(false)
                }
            )
        }
        .help(L10n.text("View Details"))
    }

    private var timeText: String {
        if event.isAllDay {
            return L10n.text("All day")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let rangeText = formatter.string(from: event.startDate)
            + " – "
            + formatter.string(from: event.endDate)

        guard showEventDuration else {
            return rangeText
        }

        return rangeText
            + " · "
            + durationText
    }

    private var durationText: String {
        let duration = max(0, event.endDate.timeIntervalSince(event.startDate))
        let totalMinutes = Int((duration / 60).rounded(.up))

        if totalMinutes >= 24 * 60 {
            let totalHours = totalMinutes / 60
            let days = totalHours / 24
            let hours = totalHours % 24

            if hours > 0 {
                return String(
                    format: L10n.text("%d days %d hours"),
                    days,
                    hours
                )
            }
            return String(format: L10n.text("%d days"), days)
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return String(
                format: L10n.text("%d hours %d minutes"),
                hours,
                minutes
            )
        }
        if hours > 0 {
            return String(format: L10n.text("%d hours"), hours)
        }
        return String(format: L10n.text("%d minutes"), totalMinutes)
    }

    private var isInProgress: Bool {
        event.startDate <= currentDate && currentDate < event.endDate
    }

    private var isExpired: Bool {
        currentDate >= event.endDate
    }

    private var endsInText: String {
        let endInterval = event.endDate.timeIntervalSince(currentDate)
        guard endInterval > 0 else {
            return L10n.text("Ended")
        }

        // 剩余时间按分钟展示，最后不足一分钟也显示为 1 分钟。
        let totalMinutes = Int((endInterval / 60).rounded(.up))

        if totalMinutes >= 24 * 60 {
            let totalHours = totalMinutes / 60
            let days = totalHours / 24
            let hours = totalHours % 24

            if hours > 0 {
                return String(
                    format: L10n.text("%d days %d hours until end"),
                    days,
                    hours
                )
            }
            return String(format: L10n.text("%d days until end"), days)
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return String(
                format: L10n.text("%d hours %d minutes until end"),
                hours,
                minutes
            )
        }
        if hours > 0 {
            return String(format: L10n.text("%d hours until end"), hours)
        }
        return String(format: L10n.text("%d minutes until end"), totalMinutes)
    }

    private var statusText: String? {
        if isInProgress {
            return L10n.text("In progress")
        }

        let startInterval = event.startDate.timeIntervalSince(currentDate)
        guard startInterval > 0,
              startInterval <= 12 * 60 * 60 else {
            return nil
        }

        // 开始前的最后不足一分钟也按 1 分钟展示。
        let totalMinutes = Int(startInterval / 60 + 0.99)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return String(
                format: L10n.text("%d hours %d minutes later"),
                hours,
                minutes
            )
        }
        if hours > 0 {
            return String(format: L10n.text("%d hours later"), hours)
        }
        return String(format: L10n.text("%d minutes later"), totalMinutes)
    }
}
