import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsStore.shared
    @State private var helperStatus: String = "Checking..."
    @State private var showClearConfirm = false

    private let formatter: ByteCountFormatter = {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt
    }()

    var body: some View {
        TabView {
            trimDefaultsTab
                .tabItem { Label("Trim", systemImage: "scissors") }

            helperTab
                .tabItem { Label("Helper", systemImage: "shield.lefthalf.filled") }

            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 340)
        .onAppear { checkHelper() }
    }

    // MARK: - Trim Defaults

    private var trimDefaultsTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Age threshold:")
                        Spacer()
                        Text("\(settings.ageThresholdMonths) months")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(settings.ageThresholdMonths) },
                        set: { settings.ageThresholdMonths = Int($0) }
                    ), in: 1...24, step: 1)
                    Text("\"Trim Now\" will delete snapshots older than this.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Quick Trim Defaults", systemImage: "clock")
            }

            Section {
                Toggle("Show notification when trim completes", isOn: $settings.trimNotifyOnComplete)
            } header: {
                Label("Notifications", systemImage: "bell")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helper

    private var helperTab: some View {
        Form {
            Section {
                HStack {
                    Text("Status:")
                    Text(helperStatus)
                        .foregroundStyle(helperStatus == "Installed" ? .green : .red)
                }

                if helperStatus == "Installed" {
                    Button("Uninstall Helper", role: .destructive) {
                        uninstallHelper()
                    }
                } else {
                    Button("Install Helper") {
                        installHelper()
                    }
                }
            } header: {
                Label("Privileged Helper", systemImage: "shield.lefthalf.filled")
            }

            Section {
                Text("The helper runs as root and performs backup deletion. "
                     + "It is installed via an admin-privileged script.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Show main window on launch", isOn: $settings.showWindowOnLaunch)
            } header: {
                Label("Launch Behavior", systemImage: "power")
            }

            Section {
                if let date = settings.lastTrimDate {
                    HStack {
                        Text("Last trim:")
                        Spacer()
                        Text(date.formatted(date: .long, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Result:")
                        Spacer()
                        Text(settings.lastTrimSummary)
                            .foregroundStyle(.secondary)
                    }
                    Button("Clear History", role: .destructive) {
                        showClearConfirm = true
                    }
                    .confirmationDialog(
                        "Clear trim history?",
                        isPresented: $showClearConfirm
                    ) {
                        Button("Clear", role: .destructive) { settings.clearTrimHistory() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The last trim date and summary will be removed.")
                    }
                } else {
                    Text("No trim history recorded yet.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Trim History", systemImage: "clock.arrow.circlepath")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helper Actions

    private func checkHelper() {
        Task {
            let client = HelperClient()
            helperStatus = await client.isInstalled ? "Installed" : "Not installed"
        }
    }

    private func installHelper() {
        let scriptPath = ".scripts/install_helper.sh"
        let fullPath = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(scriptPath)
        guard FileManager.default.fileExists(atPath: fullPath) else {
            helperStatus = "Script not found: \(scriptPath)"
            return
        }
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = [fullPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.launch()
        process.waitUntilExit()
        helperStatus = process.terminationStatus == 0 ? "Installed" : "Install failed"
    }

    private func uninstallHelper() {
        let scriptPath = ".scripts/uninstall_helper.sh"
        let fullPath = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(scriptPath)
        if FileManager.default.fileExists(atPath: fullPath) {
            let process = Process()
            process.launchPath = "/bin/bash"
            process.arguments = [fullPath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.launch()
            process.waitUntilExit()
            helperStatus = process.terminationStatus == 0 ? "Not installed" : "Uninstall failed"
        } else {
            // Fallback via osascript
            // swiftlint:disable:next line_length
            let script = "do shell script \"launchctl unload /Library/LaunchDaemons/com.ricardoleal.TimeMachineTrimmer.helper.plist; rm -f /usr/local/bin/TimeMachineTrimmer-helper /Library/LaunchDaemons/com.ricardoleal.TimeMachineTrimmer.helper.plist\" with administrator privileges"
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            helperStatus = "Not installed"
        }
    }
}
