import SwiftUI
import AppKit

enum DisplayMode: String, CaseIterable {
    case formattedDate
    case iconOnly
}

struct MenuBarLabelView: View {
    @AppStorage("displayMode")
    private var displayModeRaw = DisplayMode.iconOnly.rawValue

    @AppStorage("dateFormat")
    private var dateFormatPattern = "yyyy-MM-dd"

    @StateObject private var clock: MenuBarClock
    @State private var currentDate = Date()

    init() {
        let defaults = UserDefaults.standard
        let displayMode = DisplayMode(
            rawValue: defaults.string(forKey: "displayMode") ?? ""
        ) ?? .iconOnly
        let pattern = defaults.string(forKey: "dateFormat") ?? "yyyy-MM-dd"

        _clock = StateObject(
            wrappedValue: MenuBarClock(
                granularity: Self.updateGranularity(
                    displayMode: displayMode,
                    dateFormatPattern: pattern
                )
            )
        )
    }

    var body: some View {
        Group {
            if currentDisplayMode == .iconOnly {
                Image(nsImage: MenuBarCalendarIconImage.image(day: currentDay))
                    .interpolation(.high)
            } else {
                ZStack {
                    Text(verbatim: stableTitlePlaceholder)
                        .hidden()

                    Text(verbatim: statusTitle)
                }
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .onAppear {
            clock.setGranularity(labelUpdateGranularity)
        }
        .onReceive(clock.$date) { date in
            if currentDisplayMode == .iconOnly {
                if currentDay != Calendar.current.component(.day, from: date) {
                    currentDate = date
                }
            } else {
                let newTitle = DateFormatter.statusDateFormatter(pattern: dateFormatPattern)
                    .string(from: date)
                if newTitle != statusTitle {
                    currentDate = date
                }
            }
        }
        .onChange(of: displayModeRaw) { _ in
            clock.setGranularity(labelUpdateGranularity)
        }
        .onChange(of: dateFormatPattern) { _ in
            clock.setGranularity(labelUpdateGranularity)
        }
    }

    private var currentDisplayMode: DisplayMode {
        DisplayMode(rawValue: displayModeRaw) ?? .iconOnly
    }

    private var statusTitle: String {
        DateFormatter.statusDateFormatter(pattern: dateFormatPattern).string(from: currentDate)
    }

    private var currentDay: Int {
        Calendar.current.component(.day, from: currentDate)
    }

    private var stableTitlePlaceholder: String {
        String(statusTitle.map { $0.isNumber ? "8" : $0 })
    }

    private var labelUpdateGranularity: MenuBarClock.Granularity {
        Self.updateGranularity(
            displayMode: currentDisplayMode,
            dateFormatPattern: dateFormatPattern
        )
    }

    private static func updateGranularity(
        displayMode: DisplayMode,
        dateFormatPattern: String
    ) -> MenuBarClock.Granularity {
        if displayMode == .iconOnly {
            return .day
        }

        if hasUnquotedFormatToken(where: { $0 == "s" }, in: dateFormatPattern) {
            return .second
        }
        if hasUnquotedFormatToken(where: { $0 == "m" }, in: dateFormatPattern) {
            return .minute
        }
        if hasUnquotedFormatToken(
            where: { $0 == "H" || $0 == "h" },
            in: dateFormatPattern
        ) {
            return .hour
        }
        return .day
    }

    private func hasUnquotedFormatToken(
        where matches: (Character) -> Bool
    ) -> Bool {
        Self.hasUnquotedFormatToken(where: matches, in: dateFormatPattern)
    }

    private static func hasUnquotedFormatToken(
        where matches: (Character) -> Bool,
        in pattern: String
    ) -> Bool {
        var isQuoted = false

        for character in pattern {
            if character == "'" {
                isQuoted.toggle()
                continue
            }
            if !isQuoted && matches(character) {
                return true
            }
        }

        return false
    }
}

private final class MenuBarClock: NSObject, ObservableObject {
    @Published private(set) var date = Date()

    private let calendar = Calendar.current
    private var timer: Timer?
    private var granularity: Granularity?

    init(granularity: Granularity? = nil) {
        self.granularity = granularity

        super.init()
        if granularity != nil {
            scheduleAlignedTimer()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemTimeContextDidChange),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeContextDidChange),
            name: NSNotification.Name.NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeContextDidChange),
            name: NSNotification.Name.NSSystemTimeZoneDidChange,
            object: nil
        )
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    enum Granularity {
        case second
        case minute
        case hour
        case day
    }

    func setGranularity(_ newGranularity: Granularity) {
        guard newGranularity != granularity else { return }

        granularity = newGranularity
        scheduleAlignedTimer()
    }

    private func scheduleAlignedTimer() {
        timer?.invalidate()
        guard granularity != nil else { return }

        let now = Date()
        let component = calendarComponent
        let currentBoundary = calendar.dateInterval(of: component, for: now)?.start ?? now
        let nextBoundary = calendar.date(
            byAdding: component,
            value: 1,
            to: currentBoundary
        ) ?? now.addingTimeInterval(1)

        let timer = Timer(
            fire: nextBoundary,
            interval: 0,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.date = Date()
            self.scheduleAlignedTimer()
        }

        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var calendarComponent: Calendar.Component {
        switch granularity ?? .day {
        case .second: .second
        case .minute: .minute
        case .hour: .hour
        case .day: .day
        }
    }

    @objc private func systemTimeContextDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.date = Date()
            self.scheduleAlignedTimer()
        }
    }
}

private enum MenuBarCalendarIconImage {
    private static let pointSize = NSSize(width: 18, height: 18)
    private static let scale: CGFloat = 3
    private static var cache: [Int: NSImage] = [:]

    static func image(day: Int) -> NSImage {
        if let cachedImage = cache[day] {
            return cachedImage
        }

        let image = makeImage(day: day)
        cache[day] = image
        return image
    }

    private static func makeImage(day: Int) -> NSImage {
        let pixelWidth = Int(pointSize.width * scale)
        let pixelHeight = Int(pointSize.height * scale)

        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        representation.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(representation)

        image.lockFocusFlipped(true)
        drawCalendarIcon(day: day, in: NSRect(origin: .zero, size: pointSize))
        image.unlockFocus()

        image.isTemplate = true
        return image
    }

    private static func drawCalendarIcon(day: Int, in rect: NSRect) {
        let calendarRect = rect.insetBy(dx: 1.35, dy: 1.35)
        let outline = NSBezierPath(
            roundedRect: calendarRect,
            xRadius: 4.0,
            yRadius: 4.0
        )
        outline.lineWidth = 1.2
        NSColor.black.setStroke()
        outline.stroke()

        let headerHeight: CGFloat = 4.5
        let headerRadius: CGFloat = 2.8
        let header = NSBezierPath()
        header.move(to: NSPoint(x: calendarRect.minX, y: calendarRect.minY + headerRadius))
        header.curve(
            to: NSPoint(x: calendarRect.minX + headerRadius, y: calendarRect.minY),
            controlPoint1: NSPoint(x: calendarRect.minX, y: calendarRect.minY + headerRadius * 0.45),
            controlPoint2: NSPoint(x: calendarRect.minX + headerRadius * 0.45, y: calendarRect.minY)
        )
        header.line(to: NSPoint(x: calendarRect.maxX - headerRadius, y: calendarRect.minY))
        header.curve(
            to: NSPoint(x: calendarRect.maxX, y: calendarRect.minY + headerRadius),
            controlPoint1: NSPoint(x: calendarRect.maxX - headerRadius * 0.45, y: calendarRect.minY),
            controlPoint2: NSPoint(x: calendarRect.maxX, y: calendarRect.minY + headerRadius * 0.45)
        )
        header.line(to: NSPoint(x: calendarRect.maxX, y: calendarRect.minY + headerHeight))
        header.line(to: NSPoint(x: calendarRect.minX, y: calendarRect.minY + headerHeight))
        header.close()

        NSColor.black.setFill()
        header.fill()

        let font = NSFont.systemFont(ofSize: 8.3, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let text = NSAttributedString(string: String(day), attributes: attributes)
        let textSize = text.size()
        let textArea = calendarRect.insetBy(dx: 0.5, dy: headerHeight + 1.0)
        let textOrigin = NSPoint(
            x: textArea.midX - textSize.width / 2,
            y: textArea.midY - textSize.height / 2 + 1.45
        )
        text.draw(at: textOrigin)
    }
}

extension DateFormatter {
    private static var statusFormatterCache: [String: DateFormatter] = [:]

    static func statusDateFormatter(pattern rawPattern: String) -> DateFormatter {
        let pattern = normalizeUnsafeTokens(
            in: rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let cacheKey = pattern.isEmpty ? "yyyy-MM-dd" : pattern
        if let formatter = statusFormatterCache[cacheKey] {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.dateFormat = cacheKey
        formatter.calendar = Calendar.current
        statusFormatterCache[cacheKey] = formatter
        return formatter
    }

    /// Rewrites week-based year (Y) and day-of-year (D) tokens to their
    /// calendar-year / day-of-month counterparts, but only OUTSIDE single
    /// quotes — quoted text is literal output and must stay untouched.
    private static func normalizeUnsafeTokens(in pattern: String) -> String {
        var result = ""
        result.reserveCapacity(pattern.count)
        var isQuoted = false
        var index = pattern.startIndex

        while index < pattern.endIndex {
            let character = pattern[index]

            if character == "'" {
                isQuoted.toggle()
                result.append(character)
            } else if !isQuoted, character == "Y" || character == "D" {
                let unsafe = character
                let replacement = unsafe == "Y" ? "y" : "d"
                while index < pattern.endIndex, pattern[index] == unsafe {
                    result.append(replacement)
                    index = pattern.index(after: index)
                }
                continue
            } else {
                result.append(character)
            }

            index = pattern.index(after: index)
        }

        return result
    }
}
