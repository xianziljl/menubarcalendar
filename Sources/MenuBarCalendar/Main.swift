import SwiftUI

@main
enum MenuBarCalendarEntryPoint {
    static func main() {
        if #available(macOS 13.0, *) {
            MenuBarCalendarApp.main()
        } else {
            LegacyApplicationController.run()
        }
    }
}

@available(macOS 13.0, *)
struct MenuBarCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            CalendarPanelView()
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fallbackController: FallbackMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if #unavailable(macOS 13.0) {
            fallbackController = FallbackMenuController()
            fallbackController?.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }
}

enum LegacyApplicationController {
    private static var appDelegate: AppDelegate?

    static func run() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
