import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasLaunched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AutoTrimService.shared.start()

        let settings = SettingsStore.shared
        if settings.showWindowOnLaunch {
            WindowSetup.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            WindowSetup.mainWindow?.orderOut(nil)
        }

        checkHelperInstallOnLaunch()
    }

    private func checkHelperInstallOnLaunch() {
        let client = HelperClient()
        guard !client.isInstalled else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let alert = NSAlert()
            alert.messageText = "Install Privileged Helper"
            alert.informativeText = "TimeMachineTrimmer needs a privileged helper to delete backups. Install it now?"
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                Task {
                    do {
                        try await client.ensureInstalled()
                        DebugLogger.log("helperInstallOnLaunch: installed successfully")
                    } catch {
                        DebugLogger.log("helperInstallOnLaunch: failed — \(error.localizedDescription)")
                    }
                }
            }
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
