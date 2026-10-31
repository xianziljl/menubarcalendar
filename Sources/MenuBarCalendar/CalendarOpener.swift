import AppKit
import EventKit

enum CalendarOpener {
    static func openCalendarApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }

    static func openPermissionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(url)
    }

    static func open(_ event: CalendarEventItem) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let encodedDate = formatter.string(from: event.startDate)
        let eventID = event.calendarItemIdentifier.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? event.calendarItemIdentifier
        let urlString = "ical://ekevent/\(encodedDate)/\(eventID)?method=show&options=more"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}
