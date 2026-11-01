import AppKit
import SwiftUI

final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private var windowController: NSWindowController?

    private init() {}

    func show() {
        if let windowController {
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable]
        window.title = L10n.text("Calendar Settings")
        window.isReleasedWhenClosed = false
        window.backgroundColor = SettingsPalette.windowBackgroundNS
        window.setContentSize(NSSize(width: 420, height: hostingController.view.fittingSize.height))
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
