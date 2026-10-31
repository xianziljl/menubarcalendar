import SwiftUI
import EventKit

struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarItemIdentifier: String
    let color: Color

    static func == (lhs: CalendarEventItem, rhs: CalendarEventItem) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.isAllDay == rhs.isAllDay
            && lhs.calendarItemIdentifier == rhs.calendarItemIdentifier
    }
}

@MainActor
final class CalendarEventsModel: ObservableObject {
    @Published private(set) var hasAccess = false
    @Published private(set) var isDenied = false
    @Published private(set) var isLoading = false
    @Published private(set) var items: [CalendarEventItem] = []
    @Published private(set) var eventDots: [Date: [Color]] = [:]

    private let eventStore = EKEventStore()
    private var notificationToken: NSObjectProtocol?
    private var loadedDate: Date?
    private var loadedDisplayedMonth: Date?
    private var loadedMonthCount = 1
    private var loadedVisibleStart: Date?
    private var loadedVisibleEnd: Date?
    private var latestRequestID = UUID()
    private var dayItems: [Date: [CalendarEventItem]] = [:]

    init() {
        updateAuthorization()

        notificationToken = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.load(
                    for: self.loadedDate ?? Date(),
                    displayedMonth: self.loadedDisplayedMonth,
                    monthCount: self.loadedMonthCount,
                    isAutomaticRefresh: true
                )
            }
        }
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
    }

    func requestAccessIfNeeded() async {
        if !hasAccess {
            await requestAccess()
        }
    }

    func requestAccess() async {
        do {
            if #available(macOS 14.0, *) {
                let status = EKEventStore.authorizationStatus(for: .event)
                if status != .fullAccess {
                    try await eventStore.requestFullAccessToEvents()
                }
            } else {
                let granted = try await legacyRequestAccess()
                if !granted {
                    updateAuthorization()
                    items = []
                    return
                }
            }

            updateAuthorization()
            if let date = loadedDate {
                await load(
                    for: date,
                    displayedMonth: loadedDisplayedMonth,
                    monthCount: loadedMonthCount,
                    isAutomaticRefresh: true
                )
            }
        } catch {
            updateAuthorization()
            items = []
        }
    }

    func load(
        for date: Date,
        displayedMonth: Date? = nil,
        monthCount: Int = 1,
        isAutomaticRefresh: Bool = false
    ) async {
        let calendar = Calendar.current
        let dayKey = calendar.startOfDay(for: date)
        let targetMonth = normalizedMonth(
            for: displayedMonth ?? loadedDisplayedMonth ?? date
        )
        let monthRange = visibleRange(for: targetMonth, monthCount: monthCount)
        let isMonthLoaded = loadedVisibleStart == monthRange.start
            && loadedVisibleEnd == monthRange.end

        let requestID = UUID()
        latestRequestID = requestID
        loadedDate = date
        loadedDisplayedMonth = targetMonth
        loadedMonthCount = max(1, monthCount)

        guard hasAccess else {
            items = []
            eventDots = [:]
            return
        }

        // 点击日期时直接复用同一个月查询的分组结果。
        // 这样事项列表和格子上圆点一定来自同一份数据。
        if !isAutomaticRefresh && isMonthLoaded {
            items = dayItems[dayKey] ?? []
            return
        }

        if !isAutomaticRefresh {
            isLoading = true
        }
        defer {
            if !isAutomaticRefresh && latestRequestID == requestID {
                isLoading = false
            }
        }

        let store = eventStore
        let decodedItems: [DecodedEvent] = await Task.detached(priority: .userInitiated) {
            let predicate = store.predicateForEvents(
                withStart: monthRange.start,
                end: monthRange.end,
                calendars: nil
            )

            return store.events(matching: predicate).map { event in
                let calendarColor = event.calendar?.color ?? NSColor.systemBlue
                let rgb = calendarColor.usingColorSpace(.sRGB)
                return DecodedEvent(
                    identifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                    title: event.title ?? L10n.text("Untitled Event"),
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarItemIdentifier: event.calendarItemIdentifier,
                    red: rgb?.redComponent ?? 0.2,
                    green: rgb?.greenComponent ?? 0.45,
                    blue: rgb?.blueComponent ?? 0.9,
                    alpha: rgb?.alphaComponent ?? 1
                )
            }
        }.value

        guard latestRequestID == requestID else {
            return
        }

        let fetchedItems = decodedItems.map(calendarItem)
        var groupedItems = group(
            fetchedItems,
            from: monthRange.start,
            to: monthRange.end
        )

        var day = monthRange.start
        while day < monthRange.end {
            if groupedItems[day] == nil {
                groupedItems[day] = []
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? monthRange.end
        }

        loadedVisibleStart = monthRange.start
        loadedVisibleEnd = monthRange.end
        dayItems = groupedItems
        eventDots = eventColors(from: groupedItems)
        items = groupedItems[dayKey] ?? []
    }

    private func legacyRequestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func checkAuthorization() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return status == .authorized
    }

    private func visibleRange(for month: Date, monthCount: Int) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let monthStart = normalizedMonth(for: month)
        let monthEnd = calendar.date(
            byAdding: .month,
            value: max(1, monthCount),
            to: monthStart
        ) ?? monthStart

        return (
            start: calendar.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart,
            end: calendar.date(byAdding: .day, value: 14, to: monthEnd) ?? monthEnd
        )
    }

    private func normalizedMonth(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date
    }

    private func calendarItem(from event: DecodedEvent) -> CalendarEventItem {
        CalendarEventItem(
            id: event.identifier,
            title: event.title,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarItemIdentifier: event.calendarItemIdentifier,
            color: Color(
                .sRGB,
                red: event.red,
                green: event.green,
                blue: event.blue,
                opacity: event.alpha
            )
        )
    }

    private func group(
        _ items: [CalendarEventItem],
        from rangeStart: Date,
        to rangeEnd: Date
    ) -> [Date: [CalendarEventItem]] {
        let calendar = Calendar.current
        var groupedItems: [Date: [CalendarEventItem]] = [:]

        for item in items {
            let eventStart = max(item.startDate, rangeStart)
            let eventEnd = min(item.endDate, rangeEnd)
            var day = calendar.startOfDay(for: eventStart)

            while day < rangeEnd && day < eventEnd {
                groupedItems[day, default: []].append(item)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? eventEnd
            }
        }

        return groupedItems.mapValues(sortItems)
    }

    private func eventColors(from groupedItems: [Date: [CalendarEventItem]]) -> [Date: [Color]] {
        groupedItems.mapValues { items in
            Array(items.prefix(4).map(\.color))
        }
    }

    private func sortItems(_ items: [CalendarEventItem]) -> [CalendarEventItem] {
        items.sorted {
            if $0.isAllDay != $1.isAllDay {
                return $0.isAllDay
            }
            return $0.startDate < $1.startDate
        }
    }

    private func updateAuthorization() {
        hasAccess = checkAuthorization()
        let status = EKEventStore.authorizationStatus(for: .event)
        isDenied = status == .denied || status == .restricted
    }
}

private struct DecodedEvent: Sendable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarItemIdentifier: String
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
}
