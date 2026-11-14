import SwiftUI
import EventKit

struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarItemIdentifier: String
    let calendarTitle: String
    let calendarIdentifier: String
    let isSubscribed: Bool
    let timeZoneIdentifier: String
    let recurrenceText: String
    let recurrenceOptionRaw: String?
    let alarmText: String
    let alarmOptionRaw: String?
    let urlText: String
    let color: Color

    var canEdit: Bool {
        !isSubscribed
    }

    static func == (lhs: CalendarEventItem, rhs: CalendarEventItem) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.startDate == rhs.startDate
            && lhs.endDate == rhs.endDate
            && lhs.isAllDay == rhs.isAllDay
            && lhs.location == rhs.location
            && lhs.notes == rhs.notes
            && lhs.calendarItemIdentifier == rhs.calendarItemIdentifier
            && lhs.calendarTitle == rhs.calendarTitle
            && lhs.calendarIdentifier == rhs.calendarIdentifier
            && lhs.isSubscribed == rhs.isSubscribed
            && lhs.timeZoneIdentifier == rhs.timeZoneIdentifier
            && lhs.recurrenceText == rhs.recurrenceText
            && lhs.recurrenceOptionRaw == rhs.recurrenceOptionRaw
            && lhs.alarmText == rhs.alarmText
            && lhs.alarmOptionRaw == rhs.alarmOptionRaw
            && lhs.urlText == rhs.urlText
    }
}

@MainActor
final class CalendarEventsModel: ObservableObject {
    @Published private(set) var hasAccess = false
    @Published private(set) var isDenied = false
    @Published private(set) var isLoading = false
    @Published private(set) var items: [CalendarEventItem] = []
    @Published private(set) var eventDots: [Date: [Color]] = [:]

    func availableCalendars(currentIdentifier: String) -> [EventCalendarOption] {
        let allCalendars = eventStore.calendars(for: .event)
        let editableCalendars = allCalendars.filter {
            $0.allowsContentModifications && !$0.isSubscribed
        }

        if let currentCalendar = allCalendars.first(where: { $0.calendarIdentifier == currentIdentifier }),
           !editableCalendars.contains(where: { $0.calendarIdentifier == currentIdentifier }) {
            return EventCalendarOption.options(from: editableCalendars + [currentCalendar])
        }

        return EventCalendarOption.options(from: editableCalendars)
    }

    private let eventStore = EKEventStore()
    private var notificationToken: NSObjectProtocol?
    private var loadedDate: Date?
    private var loadedDisplayedMonth: Date?
    private var loadedMonthCount = 1
    private var loadedVisibleStart: Date?
    private var loadedVisibleEnd: Date?
    private var latestRequestID = UUID()
    private var dayItems: [Date: [CalendarEventItem]] = [:]
    private var changeNotificationTask: Task<Void, Never>?
    private var lastOwnChangeDate = Date.distantPast

    init() {
        updateAuthorization()

        notificationToken = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleCoalescedReload()
            }
        }
    }

    deinit {
        if let notificationToken {
            NotificationCenter.default.removeObserver(notificationToken)
        }
        changeNotificationTask?.cancel()
    }

    /// EKEventStoreChanged can burst (one notification per save) and each one
    /// triggers a full-month requery. Coalesce them; also skip the window
    /// right after our own save, which already refreshed the loaded events.
    private func scheduleCoalescedReload() {
        changeNotificationTask?.cancel()

        changeNotificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            guard Date().timeIntervalSince(self.lastOwnChangeDate) > 1 else { return }

            await self.load(
                for: self.loadedDate ?? Date(),
                displayedMonth: self.loadedDisplayedMonth,
                monthCount: self.loadedMonthCount,
                isAutomaticRefresh: true
            )
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
                let recurrenceRules = event.recurrenceRules ?? []
                let recurrenceOption = eventRecurrenceOption(for: recurrenceRules)
                let alarmOption = eventAlarmOption(for: event.alarms)
                return DecodedEvent(
                    identifier: event.eventIdentifier ?? event.calendarItemIdentifier,
                    title: event.title ?? L10n.text("Untitled Event"),
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location,
                    notes: event.notes,
                    calendarItemIdentifier: event.calendarItemIdentifier,
                    calendarTitle: event.calendar?.title ?? "",
                    calendarIdentifier: event.calendar?.calendarIdentifier ?? "",
                    isSubscribed: event.calendar?.isSubscribed ?? true,
                    timeZoneIdentifier: event.timeZone?.identifier ?? TimeZone.current.identifier,
                    recurrenceText: eventRecurrenceText(for: recurrenceRules),
                    recurrenceOptionRaw: recurrenceOption?.rawValue,
                    alarmText: eventAlarmText(for: event.alarms),
                    alarmOptionRaw: alarmOption?.rawValue,
                    urlText: event.url?.absoluteString ?? "",
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
            location: event.location,
            notes: event.notes,
            calendarItemIdentifier: event.calendarItemIdentifier,
            calendarTitle: event.calendarTitle,
            calendarIdentifier: event.calendarIdentifier,
            isSubscribed: event.isSubscribed,
            timeZoneIdentifier: event.timeZoneIdentifier,
            recurrenceText: event.recurrenceText,
            recurrenceOptionRaw: event.recurrenceOptionRaw,
            alarmText: event.alarmText,
            alarmOptionRaw: event.alarmOptionRaw,
            urlText: event.urlText,
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
            var eventEnd = min(item.endDate, rangeEnd)
            var day = calendar.startOfDay(for: eventStart)

            // All-day end dates are inclusive in the Calendar UI, and EventKit may
            // represent a single day with start == end. Ensure that day is included.
            if item.isAllDay && eventEnd <= day {
                eventEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? eventEnd
            }

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

    /// A recurring series shares one EventKit identifier across occurrences.
    /// Resolving by identifier alone can return the series anchor, so the exact
    /// occurrence must be matched by its occurrence date before editing/deleting.
    private func exactEvent(
        for item: CalendarEventItem,
        in store: EKEventStore
    ) -> EKEvent? {
        let directEvent = store.event(withIdentifier: item.id)
            ?? (store.calendarItem(withIdentifier: item.calendarItemIdentifier) as? EKEvent)

        if let directEvent, isSameOccurrence(directEvent, as: item) {
            return directEvent
        }

        guard let seriesIdentifier = directEvent?.eventIdentifier ?? store.event(withIdentifier: item.id)?.eventIdentifier else {
            return directEvent
        }

        let calendar = Calendar.current
        let searchStart = calendar.date(byAdding: .day, value: -1, to: item.startDate) ?? item.startDate
        let searchEnd = calendar.date(byAdding: .day, value: 1, to: item.endDate) ?? item.endDate
        let predicate = store.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: nil
        )

        return store.events(matching: predicate).first { candidate in
            candidate.eventIdentifier == seriesIdentifier
                && candidate.calendarItemIdentifier == item.calendarItemIdentifier
                && isSameOccurrence(candidate, as: item)
        } ?? directEvent
    }

    private func isSameOccurrence(
        _ event: EKEvent,
        as item: CalendarEventItem
    ) -> Bool {
        event.isAllDay == item.isAllDay
            && abs(event.occurrenceDate.timeIntervalSince(item.startDate)) < 1
            && (event.endDate == item.endDate || event.isAllDay)
    }

    func updateEvent(
        _ item: CalendarEventItem,
        title: String,
        location: String?,
        notes: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        recurrenceOption: EventRecurrenceOption,
        reminderOption: EventReminderOption,
        calendarIdentifier: String,
        urlText: String
    ) async throws {
        guard hasAccess else {
            throw CalendarEventUpdateError.accessDenied
        }
        guard item.canEdit else {
            throw CalendarEventUpdateError.subscribedEvent
        }

        let event = exactEvent(for: item, in: eventStore)

        guard let event else {
            throw CalendarEventUpdateError.eventNotFound
        }

        guard let targetCalendar = eventStore.calendar(withIdentifier: calendarIdentifier),
              targetCalendar.allowsContentModifications,
              !targetCalendar.isSubscribed else {
            throw CalendarEventUpdateError.invalidCalendar
        }

        let normalizedCalendar = Calendar.current
        let normalizedStartDate: Date
        let normalizedEndDate: Date

        if isAllDay {
            normalizedStartDate = normalizedCalendar.startOfDay(for: startDate)
            // The editing UI shows the inclusive last day (macOS Calendar style),
            // but EventKit stores the exclusive end at the midnight AFTER it, and
            // a one-day all-day event as start == end on the same midnight.
            // Saving the inclusive day directly would silently drop the last day.
            let inclusiveEnd = normalizedCalendar.startOfDay(for: max(endDate, normalizedStartDate))
            normalizedEndDate = inclusiveEnd <= normalizedStartDate
                ? normalizedStartDate
                : normalizedCalendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
        } else {
            normalizedStartDate = startDate
            normalizedEndDate = max(
                endDate,
                startDate.addingTimeInterval(60)
            )
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)

        event.title = trimmedTitle.isEmpty
            ? L10n.text("Untitled Event")
            : trimmedTitle
        event.location = trimmedLocation?.isEmpty == true ? nil : trimmedLocation
        event.notes = trimmedNotes?.isEmpty == true ? nil : trimmedNotes
        event.isAllDay = isAllDay
        event.startDate = normalizedStartDate
        event.endDate = normalizedEndDate
        event.calendar = targetCalendar

        switch recurrenceOption {
        case .custom:
            break
        case .never:
            event.recurrenceRules = nil
        case .daily:
            event.recurrenceRules = [
                EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
            ]
        case .weekly:
            event.recurrenceRules = [
                EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
            ]
        case .monthly:
            event.recurrenceRules = [
                EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
            ]
        case .yearly:
            event.recurrenceRules = [
                EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
            ]
        }

        switch reminderOption {
        case .custom:
            break
        case .none:
            event.alarms = nil
        default:
            if let offset = reminderOption.offset {
                event.alarms = [EKAlarm(relativeOffset: offset)]
            }
        }

        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            event.url = nil
        } else if let url = URL(string: trimmedURL) {
            event.url = url
        } else {
            throw CalendarEventUpdateError.invalidURL
        }

        // item refers to the occurrence shown in the popover. Saving with this
        // span turns a moved/changed series occurrence into an exception without
        // touching occurrences before or after it.
        try eventStore.save(event, span: .thisEvent, commit: true)
        lastOwnChangeDate = Date()

        // Calendar moves and all-day changes should be reflected immediately, even when
        // the EventKit change notification is delivered asynchronously.
        await refreshLoadedEvents()
    }

    func createEvent(
        title: String,
        location: String?,
        notes: String?,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        recurrenceOption: EventRecurrenceOption,
        reminderOption: EventReminderOption,
        calendarIdentifier: String,
        urlText: String
    ) async throws {
        guard hasAccess else {
            throw CalendarEventUpdateError.accessDenied
        }

        guard let targetCalendar = eventStore.calendar(withIdentifier: calendarIdentifier),
              targetCalendar.allowsContentModifications,
              !targetCalendar.isSubscribed else {
            throw CalendarEventUpdateError.invalidCalendar
        }

        let normalizedCalendar = Calendar.current
        let normalizedStartDate: Date
        let normalizedEndDate: Date

        if isAllDay {
            normalizedStartDate = normalizedCalendar.startOfDay(for: startDate)
            // Same inclusive-UI → exclusive-EventKit conversion as updateEvent:
            // a one-day all-day event stays start == end; multi-day events end
            // at the midnight after the inclusive last day.
            let inclusiveEnd = normalizedCalendar.startOfDay(for: max(endDate, normalizedStartDate))
            normalizedEndDate = inclusiveEnd <= normalizedStartDate
                ? normalizedStartDate
                : normalizedCalendar.date(byAdding: .day, value: 1, to: inclusiveEnd) ?? inclusiveEnd
        } else {
            normalizedStartDate = startDate
            normalizedEndDate = max(endDate, startDate.addingTimeInterval(60))
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = targetCalendar
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.text("Untitled Event")
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.location = location?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            ? nil
            : location?.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            ? nil
            : notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        event.isAllDay = isAllDay
        event.startDate = normalizedStartDate
        event.endDate = normalizedEndDate

        switch recurrenceOption {
        case .never:
            event.recurrenceRules = nil
        case .daily:
            event.recurrenceRules = [
                EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
            ]
        case .weekly:
            event.recurrenceRules = [
                EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
            ]
        case .monthly:
            event.recurrenceRules = [
                EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
            ]
        case .yearly:
            event.recurrenceRules = [
                EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
            ]
        case .custom:
            break
        }

        switch reminderOption {
        case .none:
            event.alarms = nil
        default:
            if let offset = reminderOption.offset {
                event.alarms = [EKAlarm(relativeOffset: offset)]
            }
        }

        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            event.url = nil
        } else if let url = URL(string: trimmedURL) {
            event.url = url
        } else {
            throw CalendarEventUpdateError.invalidURL
        }

        try eventStore.save(event, span: .thisEvent, commit: true)
        lastOwnChangeDate = Date()
        await refreshLoadedEvents()
    }

    func deleteEvent(
        _ item: CalendarEventItem,
        scope: EventDeleteScope
    ) async throws {
        guard hasAccess else {
            throw CalendarEventUpdateError.accessDenied
        }
        guard item.canEdit else {
            throw CalendarEventUpdateError.subscribedEvent
        }

        guard let event = exactEvent(for: item, in: eventStore) else {
            throw CalendarEventUpdateError.eventNotFound
        }

        let hasRecurrenceRules = item.recurrenceOptionRaw != EventRecurrenceOption.never.rawValue
            || event.recurrenceRules?.isEmpty == false
        let eventKitSpan: EKSpan = scope == .allFutureEvents && hasRecurrenceRules
            ? .futureEvents
            : .thisEvent
        try eventStore.remove(event, span: eventKitSpan, commit: true)
        lastOwnChangeDate = Date()
        await refreshLoadedEvents()
    }


    func refreshLoadedEvents() async {
        guard let date = loadedDate else { return }

        await load(
            for: date,
            displayedMonth: loadedDisplayedMonth,
            monthCount: loadedMonthCount,
            isAutomaticRefresh: true
        )
    }
}

private struct DecodedEvent: Sendable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarItemIdentifier: String
    let calendarTitle: String
    let calendarIdentifier: String
    let isSubscribed: Bool
    let timeZoneIdentifier: String
    let recurrenceText: String
    let recurrenceOptionRaw: String?
    let alarmText: String
    let alarmOptionRaw: String?
    let urlText: String
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat
}

enum EventDeleteScope {
    case thisEvent
    case allFutureEvents
}

enum CalendarEventUpdateError: LocalizedError {
    case accessDenied
    case subscribedEvent
    case eventNotFound
    case saveFailed
    case invalidURL
    case invalidCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return L10n.text("Calendar access is required to edit events.")
        case .subscribedEvent:
            return L10n.text("Subscribed events cannot be edited.")
        case .eventNotFound:
            return L10n.text("This event is no longer available.")
        case .saveFailed:
            return L10n.text("Event changes could not be saved.")
        case .invalidURL:
            return L10n.text("The URL is invalid.")
        case .invalidCalendar:
            return L10n.text("The selected calendar is invalid.")
        }
    }
}

struct EventCalendarOption: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color

    static func options(from calendars: [EKCalendar]) -> [EventCalendarOption] {
        calendars.map { calendar in
            EventCalendarOption(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: Color(nsColor: calendar.color)
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

enum EventRecurrenceOption: String, CaseIterable, Identifiable {
    case never
    case daily
    case weekly
    case monthly
    case yearly
    case custom

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .never: return L10n.text("Never")
        case .daily: return L10n.text("Daily")
        case .weekly: return L10n.text("Weekly")
        case .monthly: return L10n.text("Monthly")
        case .yearly: return L10n.text("Yearly")
        case .custom: return L10n.text("Custom")
        }
    }
}

enum EventReminderOption: String, CaseIterable, Identifiable {
    case none
    case atTime
    case minutes5
    case minutes15
    case minutes30
    case hour1
    case day1
    case custom

    var id: String { rawValue }

    var offset: TimeInterval? {
        switch self {
        case .none, .custom: return nil
        case .atTime: return 0
        case .minutes5: return -5 * 60
        case .minutes15: return -15 * 60
        case .minutes30: return -30 * 60
        case .hour1: return -60 * 60
        case .day1: return -24 * 60 * 60
        }
    }

    var displayText: String {
        switch self {
        case .none: return L10n.text("None")
        case .atTime: return L10n.text("At time of event")
        case .minutes5: return L10n.text("5 minutes before")
        case .minutes15: return L10n.text("15 minutes before")
        case .minutes30: return L10n.text("30 minutes before")
        case .hour1: return L10n.text("1 hour before")
        case .day1: return L10n.text("1 day before")
        case .custom: return L10n.text("Custom")
        }
    }
}

private func eventRecurrenceOption(for rules: [EKRecurrenceRule]) -> EventRecurrenceOption? {
    guard rules.count == 1, let rule = rules.first, rule.interval == 1, rule.recurrenceEnd == nil else {
        return rules.isEmpty ? .never : .custom
    }

    switch rule.frequency {
    case .daily: return .daily
    case .weekly: return .weekly
    case .monthly: return .monthly
    case .yearly: return .yearly
    @unknown default: return .custom
    }
}

private func eventRecurrenceText(for rules: [EKRecurrenceRule]) -> String {
    eventRecurrenceOption(for: rules)?.displayText ?? EventRecurrenceOption.custom.displayText
}

private func eventAlarmOption(for alarms: [EKAlarm]?) -> EventReminderOption? {
    guard let alarms, !alarms.isEmpty else { return EventReminderOption.none }
    guard alarms.count == 1, let alarm = alarms.first, alarm.absoluteDate == nil else {
        return .custom
    }

    return EventReminderOption.allCases.first { $0.offset == alarm.relativeOffset } ?? .custom
}

private func eventAlarmText(for alarms: [EKAlarm]?) -> String {
    eventAlarmOption(for: alarms)?.displayText ?? EventReminderOption.custom.displayText
}
