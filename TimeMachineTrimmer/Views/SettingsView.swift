import SwiftUI

private enum SettingsTab: String, CaseIterable {
    case trim = "Trim"
    case autoTrim = "Auto Trim"
    case helper = "Helper"
    case general = "General"

    var icon: String {
        switch self {
        case .trim: "scissors"
        case .autoTrim: "clock.arrow.2.circlepath"
        case .helper: "shield.lefthalf.filled"
        case .general: "gearshape"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = SettingsStore.shared
    @State private var helperStatus: String = "Checking..."
    @State private var showClearConfirm = false
    @State private var selectedTab: SettingsTab = .trim

    private func clampedValue(_ value: Int, to unit: TrimUnit) -> Int {
        min(max(value, 1), unit.maxValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            segmentPicker
            tabContent
        }
        .frame(width: 480, height: 460)
        .onAppear { checkHelper() }
    }

    private var topBar: some View {
        HStack {
            Text("Settings")
                .font(.headline)
            Spacer()
            Button(
                action: { dismiss() },
                label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            )
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var segmentPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Label(tab.rawValue, systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            Group {
                switch selectedTab {
                case .trim: trimDefaultsTab
                case .autoTrim: autoTrimTab
                case .helper: helperTab
                case .general: generalTab
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Trim Defaults

    private var trimDefaultsTab: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $settings.trimThresholdUnit) {
                    ForEach(TrimUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    TextField("", value: $settings.trimThresholdValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .id(settings.trimThresholdValue)
                        .onSubmit {
                            settings.trimThresholdValue = clampedValue(
                                settings.trimThresholdValue, to: settings.trimThresholdUnit
                            )
                        }
                    Stepper(
                        "Value",
                        value: $settings.trimThresholdValue,
                        in: 1...settings.trimThresholdUnit.maxValue
                    )
                    .labelsHidden()
                }
                Text("\"Trim Now\" will delete snapshots older than this.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)

            Toggle("Show notification when trim completes", isOn: $settings.trimNotifyOnComplete)
                .padding(12)
                .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Auto Trim

    private var autoTrimTab: some View {
        VStack(spacing: 20) {
            Toggle("Enable automatic trimming", isOn: $settings.autoTrimEnabled)
                .padding(12)
                .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)

            if settings.autoTrimEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $settings.autoTrimThresholdUnit) {
                        ForEach(TrimUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        TextField("", value: $settings.autoTrimThresholdValue, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .id(settings.autoTrimThresholdValue)
                            .onSubmit {
                                settings.autoTrimThresholdValue = clampedValue(
                                    settings.autoTrimThresholdValue, to: settings.autoTrimThresholdUnit
                                )
                            }
                        Stepper(
                            "Value",
                            value: $settings.autoTrimThresholdValue,
                            in: 1...settings.autoTrimThresholdUnit.maxValue
                        )
                        .labelsHidden()
                    }
                }
                .padding(12)
                .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let date = settings.autoTrimLastRun {
                    HStack {
                        Text("Last run:")
                        Spacer()
                        Text(date.formatted(date: .long, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Result:")
                        Spacer()
                        Text(settings.autoTrimResult)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not yet run.")
                        .foregroundStyle(.secondary)
                }
                Divider()
                Button("Run Now") {
                    Task { await AutoTrimService.shared.runNow() }
                }
                .disabled(!settings.autoTrimEnabled)
            }
            .padding(12)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper

    private var helperTab: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
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

                Text("The helper runs as root and performs backup deletion. "
                     + "It is installed via an admin-privileged script.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
            }
            .padding(12)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 4)
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(spacing: 20) {
            Toggle("Show main window on launch", isOn: $settings.showWindowOnLaunch)
                .padding(12)
                .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 6) {
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
                    Divider()
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
            }
            .padding(12)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper Actions

    private func checkHelper() {
        Task {
            let client = HelperClient()
            helperStatus = client.isInstalled ? "Installed" : "Not installed"
        }
    }

    private func installHelper() {
        Task {
            let client = HelperClient()
            do {
                try await client.ensureInstalled()
                helperStatus = "Installed"
            } catch {
                helperStatus = "Install failed: \(error.localizedDescription)"
            }
        }
    }

    private func uninstallHelper() {
        Task {
            let client = HelperClient()
            do {
                try client.uninstall()
                helperStatus = "Not installed"
            } catch {
                helperStatus = "Uninstall failed: \(error.localizedDescription)"
            }
        }
    }
}
