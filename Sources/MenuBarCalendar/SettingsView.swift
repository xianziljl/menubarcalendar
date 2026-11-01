import SwiftUI

struct SettingsView: View {
    @AppStorage("displayMode")
    private var displayModeRaw = DisplayMode.iconOnly.rawValue

    @AppStorage("dateFormat")
    private var dateFormatPattern = "yyyy-MM-dd"

    @AppStorage("showLunar")
    private var showLunar = L10n.isChinese

    @AppStorage("showHolidayBadges")
    private var showHolidayBadges = L10n.isChinese

    @AppStorage("firstWeekday")
    private var firstWeekday = 1

    @AppStorage("monthDisplayMode")
    private var monthDisplayModeRaw = MonthDisplayMode.single.rawValue

    private var isDualMonthBinding: Binding<Bool> {
        Binding(
            get: { monthDisplayModeRaw == MonthDisplayMode.dual.rawValue },
            set: { monthDisplayModeRaw = $0 ? MonthDisplayMode.dual.rawValue : MonthDisplayMode.single.rawValue }
        )
    }

    @AppStorage("dualMonthLayout")
    private var dualMonthLayoutRaw = DualMonthLayout.horizontal.rawValue

    @AppStorage("showYearSwitchButtons")
    private var showYearSwitchButtons = false

    @AppStorage("launchAtLogin")
    private var launchAtLogin = false

    @State private var formatInput = ""
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            generalSection
            calendarPanelSection
            versionFooter
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
    }

    // MARK: - Sections

    private var generalSection: some View {
        SettingsCard(title: L10n.text("General")) {
            SwitchRow(label: L10n.text("Launch at login"), isOn: $launchAtLogin)
                .disabled(!LoginItemManager.isSupported)
                .onAppear {
                    launchAtLogin = LoginItemManager.isEnabled
                }
                .onChange(of: launchAtLogin) { newValue in
                    do {
                        try LoginItemManager.setEnabled(newValue)
                        loginItemError = nil
                    } catch {
                        launchAtLogin = !newValue
                        loginItemError = error.localizedDescription
                    }
                }

            if LoginItemManager.isSupported,
               launchAtLogin,
               LoginItemManager.requiresApproval {
                RowDivider()
                HintRow(text: L10n.text("Approval is required in System Settings before it takes effect."))
            }

            if let loginItemError {
                RowDivider()
                HintRow(text: loginItemError, color: .red)
            }

            if !LoginItemManager.isSupported {
                RowDivider()
                HintRow(text: L10n.text("Launch at login requires macOS 13.0 or later."))
            }

            RowDivider()
            SegmentedRow(
                title: L10n.text("Content"),
                selection: $displayModeRaw,
                options: [
                    (DisplayMode.formattedDate.rawValue, L10n.text("Date")),
                    (DisplayMode.iconOnly.rawValue, L10n.text("Calendar Icon"))
                ]
            )

            if displayModeRaw == DisplayMode.formattedDate.rawValue {
                RowDivider()
                TextFieldRow(
                    label: L10n.text("Date format"),
                    hint: "\(L10n.text("Examples: yyyy-MM-dd EEE, M/d, HH:mm:ss")) \(L10n.text("EEE/EEEE shows the weekday. HH:mm:ss shows seconds and updates every second."))",
                    text: $formatInput
                )
                    .onAppear {
                        formatInput = dateFormatPattern
                    }
                    .onChange(of: formatInput) { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        dateFormatPattern = trimmed.isEmpty ? "yyyy-MM-dd" : trimmed
                    }
            }

            RowDivider()
            ActionRow(
                title: L10n.text("Open Privacy Settings"),
                hint: L10n.text("Calendar access is required to show events.")
            ) {
                CalendarOpener.openPermissionSettings()
            }
        }
    }

    private var calendarPanelSection: some View {
        SettingsCard(title: L10n.text("Calendar Panel")) {
            SwitchRow(label: L10n.text("Show lunar"), isOn: $showLunar)
            RowDivider()
            SwitchRow(
                label: L10n.text("Show holiday and workday badges"),
                hint: L10n.text("Holiday schedules are subject to official announcements."),
                isOn: $showHolidayBadges
            )
            RowDivider()
            SwitchRow(label: L10n.text("Show year switch buttons"), isOn: $showYearSwitchButtons)

            RowDivider()
            SwitchRow(label: L10n.text("Dual Month Display"), isOn: isDualMonthBinding)

            if monthDisplayModeRaw == MonthDisplayMode.dual.rawValue {
                RowDivider()
                SegmentedRow(
                    title: L10n.text("Dual Month Layout"),
                    selection: $dualMonthLayoutRaw,
                    options: [
                        (DualMonthLayout.horizontal.rawValue, L10n.text("Horizontal")),
                        (DualMonthLayout.vertical.rawValue, L10n.text("Vertical"))
                    ]
                )
            }

            RowDivider()
            MenuRow(
                label: L10n.text("Week starts on"),
                selection: $firstWeekday,
                options: [
                    (1, L10n.text("Sunday")),
                    (2, L10n.text("Monday")),
                    (3, L10n.text("Tuesday")),
                    (4, L10n.text("Wednesday")),
                    (5, L10n.text("Thursday")),
                    (6, L10n.text("Friday")),
                    (7, L10n.text("Saturday"))
                ]
            )
        }
    }

    private var versionFooter: some View {
        Text("\(L10n.text("Version")) \(AppInfo.version) (\(AppInfo.build))")
            .font(.caption2)
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}

// MARK: - iOS-style building blocks

/// A rounded group card with an optional section title, mimicking iOS grouped settings.
private struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }
            VStack(alignment: .leading, spacing: 0, content: content)
                .background(SettingsPalette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// iOS Settings-style grouped background palette that adapts to light/dark appearance.
enum SettingsPalette {
    static let cardBackgroundNS: NSColor = NSColor(name: nil) { appearance in
        isDarkAppearance(appearance)
            // Translucent overlays adapt to any window background:
            ? NSColor.white.withAlphaComponent(0.04)       // dark: subtle white lift
            : NSColor.black.withAlphaComponent(0.035)      // light: subtle gray tint
    }

    static var cardBackground: Color {
        Color(nsColor: cardBackgroundNS)
    }

    private static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

/// Shared app metadata read from the bundle's Info.plist.
enum AppInfo {
    static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "MenuBarCalendar"
    }

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
    }
}

/// A row with a trailing iOS-style switch.
private struct SwitchRow: View {
    let label: String
    var hint: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Toggle(String(""), isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                .accessibilityLabel(label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A row with a leading label and a trailing segmented control.
private struct SegmentedRow: View {
    let title: String
    @Binding var selection: String
    let options: [(value: String, label: String)]

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(title)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A row with a leading label and a trailing pull-down menu.
private struct MenuRow: View {
    let label: String
    @Binding var selection: Int
    let options: [(value: Int, label: String)]

    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            Picker(label, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel(label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// A row with a leading label and trailing text field, with a full-width hint below.
private struct TextFieldRow: View {
    let label: String
    let hint: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer(minLength: 12)
                TextField("YYYY-MM-DD", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A hint row inside a card.
private struct HintRow: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A full-row tappable action with a trailing chevron, iOS style.
private struct ActionRow: View {
    let title: String
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.accentColor)
                    if let hint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A hairline divider inset from the leading edge, as in iOS grouped lists.
private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
}
