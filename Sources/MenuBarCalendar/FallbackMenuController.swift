import AppKit
import SwiftUI

final class FallbackMenuController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.target = self
        item.button?.action = #selector(togglePanel)

        let hostingController = NSHostingController(rootView: MenuBarLabelView())
        item.button?.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: item.button!.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: item.button!.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: item.button!.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: item.button!.bottomAnchor)
        ])

        let panelController = NSHostingController(rootView: CalendarPanelView())
        if #available(macOS 13.0, *) {
            panelController.sizingOptions = [.preferredContentSize, .intrinsicContentSize]
        }
        popover.contentViewController = panelController
        popover.behavior = .transient
        popover.animates = true
        statusItem = item
    }

    @objc private func togglePanel() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
