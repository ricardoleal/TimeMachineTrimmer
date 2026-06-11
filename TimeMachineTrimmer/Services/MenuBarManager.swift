import AppKit

@MainActor
final class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var lastTrimItem: NSMenuItem?

    func setup(
        onScan: @escaping () -> Void,
        onShowWindow: @escaping () -> Void,
        onTrimNow: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "scissors",
            accessibilityDescription: "TimeMachineTrimmer"
        )
        statusItem?.button?.image?.isTemplate = true
        statusItem?.menu = buildMenu()

        self.onScan = onScan
        self.onShowWindow = onShowWindow
        self.onTrimNow = onTrimNow
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        addTopMenuItems(to: menu)
        menu.addItem(NSMenuItem.separator())
        addBottomMenuItems(to: menu)
        return menu
    }

    private func addTopMenuItems(to menu: NSMenu) {
        let trimItem = NSMenuItem(
            title: "Trim Now\u{2026}",
            action: #selector(trimNow(_:)),
            keyEquivalent: "t"
        )
        trimItem.keyEquivalentModifierMask = [.command, .shift]
        trimItem.target = self
        menu.addItem(trimItem)

        let showItem = NSMenuItem(
            title: "Open Main Window",
            action: #selector(showWindow(_:)),
            keyEquivalent: "o"
        )
        showItem.keyEquivalentModifierMask = [.command, .shift]
        showItem.target = self
        menu.addItem(showItem)

        let lastTrimItem = NSMenuItem(
            title: lastTrimTitle,
            action: nil,
            keyEquivalent: ""
        )
        lastTrimItem.isEnabled = false
        self.lastTrimItem = lastTrimItem
        menu.addItem(lastTrimItem)
    }

    private func addBottomMenuItems(to menu: NSMenu) {
        let scanItem = NSMenuItem(
            title: "Scan Backups",
            action: #selector(scanBackups(_:)),
            keyEquivalent: "r"
        )
        scanItem.target = self
        menu.addItem(scanItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(settingsAction(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit TimeMachineTrimmer",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private var onScan: (() -> Void)?
    private var onShowWindow: (() -> Void)?
    private var onTrimNow: (() -> Void)?
    private var onSettings: (() -> Void)?
    private var onQuit: (() -> Void)?

    private var lastTrimTitle: String {
        let settings = SettingsStore.shared
        if let date = settings.lastTrimDate {
            let dateStr = date.formatted(date: .abbreviated, time: .omitted)
            return "Last trim: \(dateStr) \u{2014} \(settings.lastTrimSummary)"
        }
        return "Last trim: never"
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        lastTrimItem?.title = lastTrimTitle
    }

    // MARK: - Actions

    @objc private func showWindow(_ sender: Any?) {
        DebugLogger.log("menuBar: Open Main Window clicked")
        onShowWindow?()
    }

    @objc private func trimNow(_ sender: Any?) {
        DebugLogger.log("menuBar: Trim Now clicked")
        onTrimNow?()
    }

    @objc private func scanBackups(_ sender: Any?) {
        DebugLogger.log("menuBar: Scan Backups clicked")
        onScan?()
    }

    @objc private func settingsAction(_ sender: Any?) {
        DebugLogger.log("menuBar: Settings clicked")
        onSettings?()
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
