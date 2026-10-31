import SwiftUI

struct CalendarPagerView: View {
    let month: Date
    @Binding var selectedDate: Date
    let firstWeekday: Int
    let showLunar: Bool
    let showHolidayBadges: Bool
    let eventDots: [Date: [Color]]
    let holidayInfo: [Date: HolidayInfo]
    let width: CGFloat
    let monthCount: Int
    let isVerticalDualLayout: Bool
    let dualMonthSpacing: CGFloat
    let onSwipe: (Int) -> Void

    private enum SlideDirection {
        case forward
        case backward
    }

    private let calendar = Calendar.current
    private let animationDuration: TimeInterval = 0.28

    @State private var sourceMonth: Date
    @State private var targetMonth: Date
    @State private var transitionTarget: Date
    @State private var slideDirection: SlideDirection = .forward
    @State private var animationProgress: CGFloat = 0
    @State private var displayedProgress: CGFloat = 0
    @State private var isAnimating = false
    @State private var pendingTarget: Date?
    @State private var dragOffset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?

    init(
        month: Date,
        selectedDate: Binding<Date>,
        firstWeekday: Int,
        showLunar: Bool,
        showHolidayBadges: Bool,
        eventDots: [Date: [Color]],
        holidayInfo: [Date: HolidayInfo],
        width: CGFloat,
        monthCount: Int,
        isVerticalDualLayout: Bool,
        dualMonthSpacing: CGFloat,
        onSwipe: @escaping (Int) -> Void
    ) {
        self.month = month
        self._selectedDate = selectedDate
        self.firstWeekday = firstWeekday
        self.showLunar = showLunar
        self.showHolidayBadges = showHolidayBadges
        self.eventDots = eventDots
        self.holidayInfo = holidayInfo
        self.width = width
        self.monthCount = monthCount
        self.isVerticalDualLayout = isVerticalDualLayout
        self.dualMonthSpacing = dualMonthSpacing
        self.onSwipe = onSwipe

        let normalizedMonth = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: month)
        ) ?? month

        _sourceMonth = State(initialValue: normalizedMonth)
        _targetMonth = State(initialValue: normalizedMonth)
        _transitionTarget = State(initialValue: normalizedMonth)
    }

    var body: some View {
        let contentWidth = max(1, width)
        let monthWidth = monthCount == 2 && !isVerticalDualLayout
            ? (contentWidth - dualMonthSpacing) / 2
            : contentWidth
        let showsAdjacentMonthDates = !(monthCount == 2 && isVerticalDualLayout)

        ZStack {
            CalendarMonthPageView(
                startMonth: sourceMonth,
                selectedDate: $selectedDate,
                firstWeekday: firstWeekday,
                showLunar: showLunar,
                showHolidayBadges: showHolidayBadges,
                eventDots: eventDots,
                holidayInfo: holidayInfo,
                monthCount: monthCount,
                isVertical: isVerticalDualLayout,
                monthWidth: monthWidth,
                monthSpacing: dualMonthSpacing,
                showsAdjacentMonthDates: showsAdjacentMonthDates
            )
            .offset(x: sourceOffset(for: contentWidth))
            .allowsHitTesting(displayedProgress < 0.5)

            CalendarMonthPageView(
                startMonth: targetMonth,
                selectedDate: $selectedDate,
                firstWeekday: firstWeekday,
                showLunar: showLunar,
                showHolidayBadges: showHolidayBadges,
                eventDots: eventDots,
                holidayInfo: holidayInfo,
                monthCount: monthCount,
                isVertical: isVerticalDualLayout,
                monthWidth: monthWidth,
                monthSpacing: dualMonthSpacing,
                showsAdjacentMonthDates: showsAdjacentMonthDates
            )
            .offset(x: targetOffset(for: contentWidth))
            .allowsHitTesting(displayedProgress >= 0.5)
            .opacity(isAnimating ? 1 : 0)
        }
        .frame(width: contentWidth)
        .padding(.vertical, 5)
        .padding(.horizontal, monthCount == 2 && !isVerticalDualLayout ? 2 : 0)
        .clipped()
        .modifier(
            CalendarProgressEffect(progress: animationProgress) { value in
                displayedProgress = value
            }
        )
        .offset(x: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    if value.translation.width < -70 {
                        onSwipe(1)
                    } else if value.translation.width > 70 {
                        onSwipe(-1)
                    }

                    withAnimation(.easeOut(duration: 0.16)) {
                        dragOffset = 0
                    }
                }
        )
        .onChange(of: month) { newValue in
            handleMonthChange(to: newValue)
        }
    }

    private func sourceOffset(for contentWidth: CGFloat) -> CGFloat {
        let slideDistance = transitionSlideDistance(for: contentWidth)
        return slideDirection == .forward
            ? -displayedProgress * slideDistance
            : displayedProgress * slideDistance
    }

    private func targetOffset(for contentWidth: CGFloat) -> CGFloat {
        let slideDistance = transitionSlideDistance(for: contentWidth)
        return slideDirection == .forward
            ? (1 - displayedProgress) * slideDistance
            : -(1 - displayedProgress) * slideDistance
    }

    private func transitionSlideDistance(for contentWidth: CGFloat) -> CGFloat {
        guard monthCount == 2, !isVerticalDualLayout else { return contentWidth }

        let monthWidth = max(1, (contentWidth - dualMonthSpacing) / 2)
        return monthWidth + dualMonthSpacing
    }

    private func handleMonthChange(to newMonth: Date) {
        let normalizedMonth = normalizedMonth(for: newMonth)

        if isAnimating {
            if calendar.isDate(normalizedMonth, equalTo: sourceMonth, toGranularity: .month) {
                reverseTransition()
            } else if calendar.isDate(normalizedMonth, equalTo: transitionTarget, toGranularity: .month) {
                pendingTarget = nil
            } else {
                pendingTarget = normalizedMonth
            }
            return
        }

        if calendar.isDate(normalizedMonth, equalTo: sourceMonth, toGranularity: .month) {
            sourceMonth = normalizedMonth
            targetMonth = normalizedMonth
            transitionTarget = normalizedMonth
            return
        }

        startTransition(from: sourceMonth, to: normalizedMonth)
    }

    private func startTransition(from current: Date, to newMonth: Date) {
        animationTask?.cancel()

        sourceMonth = current
        targetMonth = newMonth
        transitionTarget = newMonth
        slideDirection = calendar.compare(current, to: newMonth, toGranularity: .month) == .orderedAscending
            ? .forward
            : .backward
        animationProgress = 0
        displayedProgress = 0
        isAnimating = true

        withAnimation(.easeOut(duration: animationDuration)) {
            animationProgress = 1
        }

        scheduleCompletion()
    }

    private func reverseTransition() {
        pendingTarget = nil
        transitionTarget = sourceMonth

        let remainingDuration = animationDuration * max(0.08, displayedProgress)
        withAnimation(.easeOut(duration: remainingDuration)) {
            animationProgress = 0
        }

        scheduleCompletion()
    }

    private func scheduleCompletion() {
        animationTask?.cancel()

        animationTask = Task { [animationDuration] in
            let nanoseconds = UInt64((animationDuration + 0.04) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                finishTransition()
            }
        }
    }

    private func finishTransition() {
        guard isAnimating else { return }

        let completedMonth = transitionTarget
        isAnimating = false
        sourceMonth = completedMonth
        targetMonth = completedMonth
        transitionTarget = completedMonth
        animationProgress = 0
        displayedProgress = 0

        if let pendingTarget, !calendar.isDate(pendingTarget, equalTo: completedMonth, toGranularity: .month) {
            self.pendingTarget = nil
            startTransition(from: completedMonth, to: pendingTarget)
        } else {
            self.pendingTarget = nil
        }
    }

    private func normalizedMonth(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

private struct CalendarMonthPageView: View {
    let startMonth: Date
    @Binding var selectedDate: Date
    let firstWeekday: Int
    let showLunar: Bool
    let showHolidayBadges: Bool
    let eventDots: [Date: [Color]]
    let holidayInfo: [Date: HolidayInfo]
    let monthCount: Int
    let isVertical: Bool
    let monthWidth: CGFloat
    let monthSpacing: CGFloat
    let showsAdjacentMonthDates: Bool

    private let calendar = Calendar.current

    var body: some View {
        Group {
            if monthCount == 2 && isVertical {
                CalendarDualVerticalGridView(
                    startMonth: startMonth,
                    selectedDate: $selectedDate,
                    firstWeekday: firstWeekday,
                    showLunar: showLunar,
                    showHolidayBadges: showHolidayBadges,
                    eventDots: eventDots,
                    holidayInfo: holidayInfo
                )
                .frame(width: monthWidth)
            } else if monthCount == 2 {
                HStack(spacing: monthSpacing) {
                    monthView(startMonth)
                    monthView(nextMonth)
                }
            } else {
                monthView(startMonth)
            }
        }
        .frame(width: pageWidth)
    }

    private var nextMonth: Date {
        calendar.date(byAdding: .month, value: 1, to: startMonth) ?? startMonth
    }

    private var pageWidth: CGFloat {
        if monthCount == 2 && !isVertical {
            return monthWidth * 2 + monthSpacing
        }
        return monthWidth
    }

    private func monthView(_ month: Date) -> some View {
        CalendarGridView(
            month: month,
            selectedDate: $selectedDate,
            firstWeekday: firstWeekday,
            showLunar: showLunar,
            showHolidayBadges: showHolidayBadges,
            eventDots: eventDots,
                holidayInfo: holidayInfo,
                showsAdjacentMonthDates: showsAdjacentMonthDates
        )
        .frame(width: monthWidth)
    }
}

private struct CalendarDualVerticalGridView: View {
    let startMonth: Date
    @Binding var selectedDate: Date
    let firstWeekday: Int
    let showLunar: Bool
    let showHolidayBadges: Bool
    let eventDots: [Date: [Color]]
    let holidayInfo: [Date: HolidayInfo]

    private let calendar = Calendar.current
    private let rowCount = 10

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let cellDate = date(forRow: row, column: column)

                        CalendarCellView(
                            date: cellDate,
                            month: month(for: cellDate),
                            selectedDate: selectedDate,
                            showLunar: showLunar,
                            showHolidayBadges: showHolidayBadges,
                            dotColors: eventDots[calendar.startOfDay(for: cellDate)] ?? [],
                            holidayInfo: holidayInfo[calendar.startOfDay(for: cellDate)]
                        ) {
                            selectedDate = cellDate
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var firstDay: Date {
        normalizedMonth(for: startMonth)
    }

    private var nextMonth: Date {
        calendar.date(byAdding: .month, value: 1, to: firstDay) ?? firstDay
    }

    private var leadingEmptyDays: Int {
        let weekday = calendar.component(.weekday, from: firstDay)
        return (weekday - firstWeekday + 7) % 7
    }

    private func date(forRow row: Int, column: Int) -> Date {
        let dayOffset = row * 7 + column - leadingEmptyDays
        return calendar.date(byAdding: .day, value: dayOffset, to: firstDay) ?? firstDay
    }

    private func month(for date: Date) -> Date {
        if calendar.isDate(date, equalTo: firstDay, toGranularity: .month) {
            return firstDay
        }
        if calendar.isDate(date, equalTo: nextMonth, toGranularity: .month) {
            return nextMonth
        }
        return calendar.compare(date, to: firstDay, toGranularity: .day) == .orderedAscending
            ? firstDay
            : nextMonth
    }

    private func normalizedMonth(for date: Date) -> Date {
        calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date
    }
}

private struct CalendarProgressEffect: GeometryEffect {
    var progress: CGFloat
    let onChange: (CGFloat) -> Void

    var animatableData: CGFloat {
        get {
            progress
        }
        set {
            progress = newValue
            let callback = onChange
            DispatchQueue.main.async {
                callback(newValue)
            }
        }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform.identity)
    }
}
