import SwiftUI

struct NewEventPopoverView: View {
    static let popoverWindowIdentifier = NSUserInterfaceItemIdentifier(
        "MenuBarCalendarNewEventPopover"
    )

    let selectedDate: Date
    let eventsModel: CalendarEventsModel
    var onCreated: () -> Void = {}

    @State private var title = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var urlText = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var isAllDay = false
    @State private var recurrenceSelection = EventRecurrenceOption.never
    @State private var reminderSelection = EventReminderOption.none
    @State private var calendarIdentifier = ""
    @State private var calendarOptions: [EventCalendarOption] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var suppressSetup = true
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                TextField(L10n.text("New Event"), text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)

                CalendarDropdownPicker(
                    options: calendarOptions,
                    selection: $calendarIdentifier
                )
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 24, alignment: .trailing)
            }

            TextField(L10n.text("Add Location"), text: $location)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.top, 2)

            Divider()
                .overlay(Color.primary.opacity(0.12))

            formRows

            Divider()
                .overlay(Color.primary.opacity(0.12))

            notesField

            TextField(L10n.text("Add URL"), text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer(minLength: 0)

                Button {
                    Task { await createEvent() }
                } label: {
                    Text(L10n.text("Add"))
                        .frame(minWidth: 48)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSaving)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 248, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            PopoverWindowIdentifierAccessor(
                identifier: Self.popoverWindowIdentifier
            )
        )
        .onAppear {
            prepareInitialValues()
            calendarOptions = eventsModel.availableCalendars(currentIdentifier: "")
            let personalTitle = L10n.text("Personal")
            calendarIdentifier = calendarOptions.first { option in
                option.title == personalTitle
                    || option.title.localizedCaseInsensitiveCompare("Personal") == .orderedSame
            }?.id ?? calendarOptions.first?.id ?? ""
        }
        .onChange(of: isAllDay) { newValue in
            updateDates(forAllDay: newValue)
        }
        .onChange(of: startDate) { _ in normalizeDates() }
        .onChange(of: endDate) { _ in normalizeDates() }
    }

    private var formRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            formRow(L10n.text("All day")) {
                Toggle("", isOn: $isAllDay)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            formRow(L10n.text("Start time")) {
                if isAllDay {
                    Text(dateText(startDate))
                        .font(.system(size: 13))
                } else {
                    DatePicker(
                        "",
                        selection: $startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }
            }

            formRow(L10n.text("End time")) {
                if isAllDay {
                    Text(dateText(endDate))
                        .font(.system(size: 13))
                } else {
                    DatePicker(
                        "",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }
            }

            formRow(L10n.text("Repeat")) {
                Picker("", selection: $recurrenceSelection) {
                    ForEach(
                        EventRecurrenceOption.allCases.filter { $0 != .custom }
                    ) { option in
                        Text(option.displayText).tag(option)
                    }
                }
                .labelsHidden()
                .controlSize(.regular)
                .frame(maxWidth: 180, alignment: .leading)
            }

            formRow(L10n.text("Alert")) {
                Picker("", selection: $reminderSelection) {
                    ForEach(
                        EventReminderOption.allCases.filter { $0 != .custom }
                    ) { option in
                        Text(option.displayText).tag(option)
                    }
                }
                .labelsHidden()
                .controlSize(.regular)
                .frame(maxWidth: 180, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var notesField: some View {
        if #available(macOS 13.0, *) {
            TextField(
                L10n.text("Add Notes"),
                text: $notes,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineLimit(1...4)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            TextField(L10n.text("Add Notes"), text: $notes)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
    }

    private func formRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 62, alignment: .trailing)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func prepareInitialValues() {
        guard suppressSetup else { return }
        suppressSetup = false

        let start: Date
        if calendar.isDate(selectedDate, inSameDayAs: Date()) {
            let components = calendar.dateComponents([.hour, .minute], from: Date())
            start = calendar.date(
                bySettingHour: components.hour ?? 9,
                minute: components.minute ?? 0,
                second: 0,
                of: selectedDate
            ) ?? selectedDate
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        }

        startDate = start
        endDate = start.addingTimeInterval(60 * 60)
    }

    private func updateDates(forAllDay allDay: Bool) {
        if allDay {
            startDate = calendar.startOfDay(for: startDate)
            endDate = calendar.startOfDay(for: startDate)
        } else {
            let time = calendar.dateComponents([.hour, .minute], from: Date())
            startDate = calendar.date(
                bySettingHour: time.hour ?? 9,
                minute: time.minute ?? 0,
                second: 0,
                of: startDate
            ) ?? startDate
            endDate = startDate.addingTimeInterval(60 * 60)
        }
    }

    private func normalizeDates() {
        guard endDate < startDate else { return }
        endDate = isAllDay
            ? startDate
            : startDate.addingTimeInterval(60 * 60)
    }

    private func createEvent() async {
        guard !isSaving else { return }

        isSaving = true
        errorMessage = nil

        do {
            try await eventsModel.createEvent(
                title: title,
                location: location,
                notes: notes,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                recurrenceOption: recurrenceSelection,
                reminderOption: reminderSelection,
                calendarIdentifier: calendarIdentifier,
                urlText: urlText
            )
            onCreated()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
