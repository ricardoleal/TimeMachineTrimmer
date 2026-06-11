import SwiftUI

@main
struct TimeMachineTrimmerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = BackupViewModel()
    private let menuBarManager = MenuBarManager()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(viewModel)
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Backups") {
                    Task { await viewModel.checkPermissionsAndScan() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.state != .ready && viewModel.state != .scanned)
            }

            CommandMenu("Actions") {
                Button("Preview Deletion") {
                    viewModel.computePreview()
                }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(viewModel.state != .scanned)

                Button("Execute Deletion") {
                    Task { await viewModel.executeDeletion() }
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(viewModel.state != .scanned)

                Divider()

                Button("Search Backups") {
                    NotificationCenter.default.post(name: NSNotification.Name("focusSearch"), object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(viewModel.state != .scanned)
            }
        }
        .onChange(of: true) { _, _ in }
    }

    init() {
        menuBarManager.setup(
            onScan: {
                NSApp.unhide(nil)
                NSApp.activate()
                WindowSetup.mainWindow?.makeKeyAndOrderFront(nil)
                NotificationCenter.default.post(name: NSNotification.Name("menuBarScan"), object: nil)
            },
            onShowWindow: {
                NSApp.unhide(nil)
                NSApp.activate()
                WindowSetup.mainWindow?.makeKeyAndOrderFront(nil)
            },
            onTrimNow: {
                NSApp.unhide(nil)
                NSApp.activate()
                WindowSetup.mainWindow?.makeKeyAndOrderFront(nil)
                NotificationCenter.default.post(name: NSNotification.Name("menuBarTrimNow"), object: nil)
            },
            onSettings: {
                NSApp.unhide(nil)
                NSApp.activate()
                WindowSetup.mainWindow?.makeKeyAndOrderFront(nil)
                NotificationCenter.default.post(name: NSNotification.Name("menuBarOpenSettings"), object: nil)
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
    }
}
