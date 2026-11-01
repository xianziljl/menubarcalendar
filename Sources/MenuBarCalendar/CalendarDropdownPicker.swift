import SwiftUI
import AppKit

struct CalendarDropdownPicker: NSViewRepresentable {
    let options: [EventCalendarOption]
    @Binding var selection: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.controlSize = .regular
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        button.lineBreakMode = .byTruncatingTail
        button.preferredEdge = .maxY
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        context.coordinator.rebuild(button, options: options, selection: selection)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        let selectedIdentifier = button.selectedItem?.representedObject as? String

        if coordinator.lastOptions != options {
            coordinator.rebuild(button, options: options, selection: selection)
            return
        }

        if selectedIdentifier != selection {
            if let item = button.menu?.items.first(where: {
                $0.representedObject as? String == selection
            }) {
                button.select(item)
            } else {
                coordinator.rebuild(button, options: options, selection: selection)
            }
        }

        coordinator.lastSelection = selection
    }

    @MainActor
    final class Coordinator: NSObject {
        private let parent: CalendarDropdownPicker
        var lastOptions: [EventCalendarOption] = []
        var lastSelection: String = ""

        init(parent: CalendarDropdownPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let identifier = sender.selectedItem?.representedObject as? String else { return }
            parent.selection = identifier
            lastSelection = identifier
        }

        func rebuild(_ button: NSPopUpButton, options: [EventCalendarOption], selection: String) {
            lastOptions = options
            lastSelection = selection
            button.removeAllItems()

            for option in options {
                let item = NSMenuItem(
                    title: option.title,
                    action: nil,
                    keyEquivalent: ""
                )
                item.image = Self.colorImage(for: option.color)
                item.representedObject = option.id
                button.menu?.addItem(item)
            }

            if let selectedItem = button.menu?.items.first(where: {
                $0.representedObject as? String == selection
            }) {
                button.select(selectedItem)
            }
        }

        private static func colorImage(for color: Color) -> NSImage {
            let size = NSSize(width: 10, height: 10)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor(color).withAlphaComponent(1).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5).fill()
                return true
            }
            image.isTemplate = false
            return image
        }
    }
}
