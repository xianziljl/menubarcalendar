import SwiftUI

struct EventDetailPopoverView: View {
    static let popoverWindowIdentifier = NSUserInterfaceItemIdentifier(
        "MenuBarCalendarEventDetailPopover"
    )

    let event: CalendarEventItem
    let eventsModel: CalendarEventsModel
    var onDeleted: () -> Void = {}

    @State private var editTitle = ""
    @State private var editLocation = ""
    @State private var editNotes = ""
    @State private var editURL = ""
    @State private var editStartDate = Date()
    @State private var editEndDate = Date()
    @State private var editIsAllDay = false
    @State private var recurrenceSelection = EventRecurrenceOption.never
    @State private var reminderSelection = EventReminderOption.none
    @State private var editCalendarIdentifier = ""
    @State private var calendarOptions: [EventCalendarOption] = []
    @State private var isSaving = false
    @State private var pendingSave = false
    @State private var hasUnsavedChanges = false
    @State private var suppressAutoSave = true
    @State private var saveTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var popoverHeight: CGFloat = 0
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if showsLocationField {
                if event.canEdit {
                    TextField(L10n.text("Add Location"), text: $editLocation)
                        .textFieldStyle(.plain)
                        .font(.system(.body))
                        .padding(.top, 2)
                        .onChange(of: editLocation) { _ in scheduleSave() }
                } else {
                    Text(editLocation)
                        .font(.system(.body))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .overlay(Color.primary.opacity(0.12))
            }

            formRows

            if showsNotesField || showsURLField {
                Divider()
                    .overlay(Color.primary.opacity(0.12))

                if showsNotesField {
                    notesField
                        .disabled(!event.canEdit)
                }

                if showsURLField {
                    if event.canEdit {
                        TextField(L10n.text("Add URL"), text: $editURL)
                            .textFieldStyle(.plain)
                            .font(.system(.body))
                            .onChange(of: editURL) { _ in scheduleSave() }
                    } else {
                        Text(editURL)
                            .font(.system(.body))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.subheadline))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
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
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PopoverHeightKey.self,
                    value: geometry.size.height
                )
            }
        )
        .frame(
            width: 248,
            height: popoverHeight > 0 ? popoverHeight : nil,
            alignment: .topLeading
        )
        .onPreferenceChange(PopoverHeightKey.self) { height in
            popoverHeight = height.rounded(.up)
        }
        .confirmationDialog(
            L10n.text("Delete Event"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if isRecurringEvent {
                Button(
                    L10n.text("Delete This Event Only"),
                    role: .destructive
                ) {
                    Task { await deleteEvent(scope: .thisEvent) }
                }
                Button(
                    L10n.text("Delete All Future Events"),
                    role: .destructive
                ) {
                    Task { await deleteEvent(scope: .allFutureEvents) }
                }
            } else {
                Button(L10n.text("Delete"), role: .destructive) {
                    Task { await deleteEvent(scope: .thisEvent) }
                }
            }
            Button(L10n.text("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("This action cannot be undone."))
        }
        .onAppear {
            prepareFormFields()
            calendarOptions = eventsModel.availableCalendars(
                currentIdentifier: event.calendarIdentifier
            )
            Task { @MainActor in
                suppressAutoSave = false
            }
        }
        .onChange(of: editIsAllDay) { isAllDay in
            updateDatesForAllDay(isAllDay)
            scheduleSave()
        }
        .onChange(of: editTitle) { _ in scheduleSave() }
        .onChange(of: editStartDate) { _ in scheduleSave() }
        .onChange(of: editEndDate) { _ in scheduleSave() }
        .onChange(of: recurrenceSelection) { _ in scheduleSave() }
        .onChange(of: reminderSelection) { _ in scheduleSave() }
        .onChange(of: editCalendarIdentifier) { _ in scheduleSave() }
        .onDisappear {
            if hasUnsavedChanges {
                saveTask?.cancel()
                Task { await save() }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if event.canEdit {
                TextField(L10n.text("Title"), text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(.title2).weight(.bold))
                    .lineLimit(2)
                    .onChange(of: editTitle) { _ in scheduleSave() }
            } else {
                Text(editTitle)
                    .font(.system(.title2).weight(.bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if event.canEdit {
                CalendarDropdownPicker(
                    options: calendarOptions,
                    selection: $editCalendarIdentifier
                )
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 24, alignment: .trailing)
                .help(L10n.text("Calendar Color"))
            } else {
                readOnlyCalendarIndicator
            }
            }
        }

    private var isRecurringEvent: Bool {
        event.recurrenceOptionRaw != EventRecurrenceOption.never.rawValue
    }

    private var showsLocationField: Bool {
        event.canEdit || !editLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsNotesField: Bool {
        event.canEdit || !editNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsURLField: Bool {
        event.canEdit || !editURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedCalendarColor: Color {
        calendarOptions.first { $0.id == editCalendarIdentifier }?.color ?? event.color
    }

    private var selectedCalendarTitle: String {
        let optionTitle = calendarOptions.first { $0.id == editCalendarIdentifier }?.title
        return optionTitle ?? (event.calendarTitle.isEmpty ? L10n.text("Calendar") : event.calendarTitle)
    }

    private var readOnlyCalendarIndicator: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(selectedCalendarColor)
                .frame(width: 10, height: 10)

            Text(selectedCalendarTitle)
                .font(.system(.callout).weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 92, alignment: .trailing)
        .help(selectedCalendarTitle)
    }

    @ViewBuilder
    private var formRows: some View {
        if event.canEdit {
            editableFormRows
        } else {
            readOnlyFormRows
        }
    }

    private var editableFormRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            formRow(L10n.text("All day")) {
                Toggle("", isOn: $editIsAllDay)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            formRow(L10n.text("Start time")) {
                if editIsAllDay {
                    Text(dateText(editStartDate))
                        .font(.system(.body))
                } else {
                    DatePicker(
                        "",
                        selection: $editStartDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }
            }

            formRow(L10n.text("End time")) {
                if editIsAllDay {
                    DatePicker(
                        "",
                        selection: $editEndDate,
                        in: editStartDate...,
                        displayedComponents: [.date]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                } else {
                    DatePicker(
                        "",
                        selection: $editEndDate,
                        in: editStartDate...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }
            }

            formRow(L10n.text("Repeat")) {
                Picker("", selection: $recurrenceSelection) {
                    ForEach(EventRecurrenceOption.allCases) { option in
                        Text(option.displayText).tag(option)
                    }
                }
                .labelsHidden()
                .controlSize(.regular)
                .frame(maxWidth: 180, alignment: .leading)
            }

            formRow(L10n.text("Alert")) {
                Picker("", selection: $reminderSelection) {
                    ForEach(EventReminderOption.allCases) { option in
                        Text(option.displayText).tag(option)
                    }
                }
                .labelsHidden()
                .controlSize(.regular)
                .frame(maxWidth: 180, alignment: .leading)
            }
        }
    }

    private var readOnlyFormRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            formRow(L10n.text("All day")) {
                Text(editIsAllDay ? L10n.text("On") : L10n.text("Off"))
                    .font(.system(.body))
            }

            formRow(L10n.text("Start time")) {
                Text(dateTimeText(editStartDate, isAllDay: editIsAllDay))
                    .font(.system(.body))
                    .fixedSize(horizontal: false, vertical: true)
            }

            formRow(L10n.text("End time")) {
                Text(dateTimeText(editEndDate, isAllDay: editIsAllDay))
                    .font(.system(.body))
                    .fixedSize(horizontal: false, vertical: true)
            }

            formRow(L10n.text("Repeat")) {
                Text(recurrenceSelection.displayText)
                    .font(.system(.body))
            }

            formRow(L10n.text("Alert")) {
                Text(reminderSelection.displayText)
                    .font(.system(.body))
            }
        }
    }

    @ViewBuilder
    private var notesField: some View {
        if !event.canEdit {
            Text(editNotes)
                .font(.system(.body))
                .fixedSize(horizontal: false, vertical: true)
        } else if #available(macOS 13.0, *) {
            TextField(
                L10n.text("Add Notes"),
                text: $editNotes,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(.body))
            .lineLimit(1...4)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: editNotes) { _ in scheduleSave() }
        } else {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $editNotes)
                    .font(.system(.body))
                    .frame(height: 42)
                    .eventDetailHiddenScrollBackground()

                if editNotes.isEmpty {
                    Text(L10n.text("Add Notes"))
                        .font(.system(.body))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: editNotes) { _ in scheduleSave() }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                CalendarOpener.open(event)
            } label: {
                Text(L10n.text("Open in Calendar"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(L10n.text("Open in Calendar"))

            if event.canEdit {
                Spacer(minLength: 0)

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Text(L10n.text("Delete"))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.text("Delete Event"))
            }
        }
        .padding(.top, 2)
    }

    private func formRow(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(.system(.callout))
                .foregroundStyle(.primary)
                .frame(width: 62, alignment: .trailing)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dateTimeText(_ date: Date, isAllDay: Bool) -> String {
        guard !isAllDay else { return dateText(date) }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func updateDatesForAllDay(_ isAllDay: Bool) {
        if isAllDay {
            editStartDate = calendar.startOfDay(for: editStartDate)
            // Keep the selected span; only clamp when end moved before start.
            // The editing UI shows all-day end dates inclusively (same as
            // macOS Calendar), so a multi-day span must survive the toggle.
            let dayEnd = calendar.startOfDay(for: editEndDate)
            editEndDate = dayEnd < editStartDate ? editStartDate : dayEnd
        } else if editEndDate <= editStartDate {
            editEndDate = editStartDate.addingTimeInterval(60 * 60)
        }
    }

    private func prepareFormFields() {
        editTitle = event.title
        editLocation = event.location ?? ""
        editNotes = event.notes ?? ""
        editURL = event.urlText
        editStartDate = event.startDate
        editEndDate = inclusiveEndDate(for: event.endDate, isAllDay: event.isAllDay)
        editIsAllDay = event.isAllDay
        editCalendarIdentifier = event.calendarIdentifier
        recurrenceSelection = EventRecurrenceOption(
            rawValue: event.recurrenceOptionRaw ?? EventRecurrenceOption.custom.rawValue
        ) ?? .custom
        reminderSelection = EventReminderOption(
            rawValue: event.alarmOptionRaw ?? EventReminderOption.custom.rawValue
        ) ?? .custom
        errorMessage = nil
    }

    private func save() async {
        guard event.canEdit else { return }
        guard !isSaving else {
            pendingSave = true
            return
        }

        isSaving = true
        errorMessage = nil

        do {
            try await eventsModel.updateEvent(
                event,
                title: editTitle,
                location: editLocation,
                notes: editNotes,
                startDate: editStartDate,
                endDate: editEndDate,
                isAllDay: editIsAllDay,
                recurrenceOption: recurrenceSelection,
                reminderOption: reminderSelection,
                calendarIdentifier: editCalendarIdentifier,
                urlText: editURL
            )
            hasUnsavedChanges = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
        if pendingSave {
            pendingSave = false
            scheduleSave()
        }
    }

    private func deleteEvent(scope: EventDeleteScope) async {
        guard event.canEdit else { return }

        // A pending auto-save must not race with EventKit deletion or recreate a
        // stale occurrence after the user has confirmed removal.
        saveTask?.cancel()
        hasUnsavedChanges = false
        pendingSave = false
        isSaving = true
        errorMessage = nil

        do {
            try await eventsModel.deleteEvent(event, scope: scope)
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func scheduleSave() {
        guard event.canEdit, !suppressAutoSave else { return }

        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func inclusiveEndDate(for date: Date, isAllDay: Bool) -> Date {
        guard isAllDay else { return date }

        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        guard time.hour == 0, time.minute == 0, time.second == 0 else {
            return date
        }

        return calendar.date(byAdding: .day, value: -1, to: date) ?? date
    }
}

private struct PopoverHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HiddenTextEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content.background(Color.clear)
        }
    }
}

private extension View {
    func eventDetailHiddenScrollBackground() -> some View {
        modifier(HiddenTextEditorBackground())
    }
}

struct PopoverWindowIdentifierAccessor: NSViewRepresentable {
    let identifier: NSUserInterfaceItemIdentifier

    func makeNSView(context: Context) -> NSView {
        IdentifierView(identifier: identifier)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class IdentifierView: NSView {
        let windowIdentifier: NSUserInterfaceItemIdentifier

        init(identifier: NSUserInterfaceItemIdentifier) {
            self.windowIdentifier = identifier
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = windowIdentifier
        }
    }
}
