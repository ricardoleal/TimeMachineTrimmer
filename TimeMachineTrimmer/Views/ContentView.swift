import SwiftUI

struct ContentView: View {
    @Environment(BackupViewModel.self) private var viewModel
    @State private var showTrimNowSheet = false
    @State private var showSettingsSheet = false

    var body: some View {
        ZStack {
            DashboardView()
                .overlay {
                    if viewModel.state == .scanning {
                        Color.black.opacity(0.12)
                    }
                }
                .overlay {
                    if viewModel.state == .scanning {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Scanning backups...")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.15), radius: 16)
                    }
                }
                .onAppear {
                    viewModel.loadDestinations()
                    viewModel.startStatusPolling()
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("menuBarScan"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        Task { await viewModel.checkPermissionsAndScan() }
                    }
                }

            Color.clear
                .sheet(isPresented: .constant(viewModel.state == .previewing)) {
                    PreviewSheet()
                        .interactiveDismissDisabled()
                }
            Color.clear
                .sheet(isPresented: .constant(viewModel.state == .deleting)) {
                    ProgressSheet()
                        .interactiveDismissDisabled()
                }
            if case .done = viewModel.state, !viewModel.isTrimNowActive {
                Color.clear
                    .sheet(isPresented: .constant(true)) {
                        ResultSheet()
                    }
            }
            if case .error(let message) = viewModel.state {
                Color.clear
                    .alert("Error", isPresented: .constant(true)) {
                        Button("OK") { viewModel.state = .ready }
                    } message: {
                        Text(message)
                    }
            }
        }
        .sheet(isPresented: Bindable(viewModel).needsPermissionSheet) {
            PermissionView()
        }
        .sheet(isPresented: $showTrimNowSheet) {
            TrimNowSheet()
                .environment(viewModel)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("menuBarTrimNow"))) { _ in
            showTrimNowSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("menuBarOpenSettings"))) { _ in
            showSettingsSheet = true
        }
        .background(WindowSetup())
        .tint(Color.accentTeal)
    }
}

struct WindowSetup: NSViewRepresentable {
    private static let closeDelegate = WindowCloseDelegate()
    static var mainWindow: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.styleMask.insert(.fullSizeContentView)
                window.setContentSize(NSSize(width: 960, height: 520))
                window.minSize = NSSize(width: 760, height: 400)
                window.isReleasedWhenClosed = false
                window.delegate = Self.closeDelegate
                Self.mainWindow = window
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class WindowCloseDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
