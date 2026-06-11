import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasLaunched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsStore.shared
        if settings.showWindowOnLaunch {
            WindowSetup.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else if !hasLaunched {
            hasLaunched = true
            let alert = NSAlert()
            alert.messageText = "TimeMachineTrimmer"
            alert.informativeText = "Running in your menu bar."
            alert.runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            NSApp.unhide(nil)
            WindowSetup.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
        return true
    }
}
