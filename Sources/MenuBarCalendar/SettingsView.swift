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

    @AppStorage("dualMonthLayout")
    private var dualMonthLayoutRaw = DualMonthLayout.horizontal.rawValue

    @AppStorage("showYearSwitchButtons")
    private var showYearSwitchButtons = false

    @AppStorage("launchAtLogin")
    private var launchAtLogin = false

    @State private var formatInput = ""
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("General"))
                    .font(.headline)

                Toggle(L10n.text("Launch at login"), isOn: $launchAtLogin)
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
                    Text(L10n.text("Approval is required in System Settings before it takes effect."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !LoginItemManager.isSupported {
                    Text(L10n.text("Launch at login requires macOS 13.0 or later."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("Menu Bar Display"))
                    .font(.headline)

                Picker(L10n.text("Content"), selection: $displayModeRaw) {
                    Text(L10n.text("Date")).tag(DisplayMode.formattedDate.rawValue)
                    Text(L10n.text("Calendar Icon")).tag(DisplayMode.iconOnly.rawValue)
                }
                .pickerStyle(.segmented)

                if displayModeRaw == DisplayMode.formattedDate.rawValue {
                    TextField("YYYY-MM-DD", text: $formatInput)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            formatInput = dateFormatPattern
                        }
                        .onChange(of: formatInput) { newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            dateFormatPattern = trimmed.isEmpty ? "yyyy-MM-dd" : trimmed
                        }

                    Text(L10n.text("Examples: yyyy-MM-dd EEE, M/d, HH:mm:ss"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(L10n.text("EEE/EEEE shows the weekday. HH:mm:ss shows seconds and updates every second."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("Calendar Panel"))
                    .font(.headline)

                Toggle(L10n.text("Show lunar"), isOn: $showLunar)
                Toggle(L10n.text("Show holiday and workday badges"), isOn: $showHolidayBadges)
                Toggle(L10n.text("Show year switch buttons"), isOn: $showYearSwitchButtons)

                Picker(L10n.text("Month Display"), selection: $monthDisplayModeRaw) {
                    Text(L10n.text("Single Month")).tag(MonthDisplayMode.single.rawValue)
                    Text(L10n.text("Dual Month")).tag(MonthDisplayMode.dual.rawValue)
                }
                .pickerStyle(.segmented)

                if monthDisplayModeRaw == MonthDisplayMode.dual.rawValue {
                    Picker(L10n.text("Dual Month Layout"), selection: $dualMonthLayoutRaw) {
                        Text(L10n.text("Horizontal")).tag(DualMonthLayout.horizontal.rawValue)
                        Text(L10n.text("Vertical")).tag(DualMonthLayout.vertical.rawValue)
                    }
                    .pickerStyle(.segmented)
                }

                Picker(L10n.text("Week starts on"), selection: $firstWeekday) {
                    Text(L10n.text("Sunday")).tag(1)
                    Text(L10n.text("Monday")).tag(2)
                    Text(L10n.text("Tuesday")).tag(3)
                    Text(L10n.text("Wednesday")).tag(4)
                    Text(L10n.text("Thursday")).tag(5)
                    Text(L10n.text("Friday")).tag(6)
                    Text(L10n.text("Saturday")).tag(7)
                }
                .pickerStyle(.menu)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("Calendar Access"))
                    .font(.headline)
                Text(L10n.text("Calendar access is required to show events."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(L10n.text("Open Privacy Settings")) {
                    CalendarOpener.openPermissionSettings()
                }
            }
        }
        .padding(22)
        .frame(width: 380, alignment: .leading)
    }
}
