import SwiftUI

private enum TrimPhase {
    case configure
    case scanning
    case preview(count: Int)
    case deleting
    case done(BackupViewModel.DeletionResult)
}

struct TrimNowSheet: View {
    @Environment(BackupViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var phase: TrimPhase = .configure
    @State private var thresholdValue: Int = SettingsStore.shared.trimThresholdValue
    @State private var thresholdUnit: TrimUnit = SettingsStore.shared.trimThresholdUnit
    @State private var progressText: String = ""

    private let formatter = ByteCountFormatter()

    private var isRunning: Bool {
        if case .scanning = phase { true } else if case .deleting = phase { true } else { false }
    }

    private var previewCount: Int {
        if case .preview(let count) = phase { count } else { 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Group {
                switch phase {
                case .configure:
                    configureView
                case .scanning:
                    scanningView
                case .preview:
                    previewView
                case .deleting:
                    deletingView
                case .done(let result):
                    doneView(result)
                }
            }
        }
        .frame(width: 380)
        .interactiveDismissDisabled(isRunning)
        .onDisappear {
            viewModel.isTrimNowActive = false
        }
    }

    private var topBar: some View {
        HStack {
            Text("Trim Backups")
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
            .disabled(isRunning)
            .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Configure

    private var configureView: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text("Delete snapshots older than")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(thresholdValue) \(thresholdUnit.displayName(count: thresholdValue))")
                    .font(.title)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.vertical, 4)
            }

            VStack(spacing: 8) {
                Picker("", selection: $thresholdUnit) {
                    ForEach(TrimUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: thresholdUnit) { _, newUnit in
                    thresholdValue = min(thresholdValue, newUnit.maxValue)
                }

                HStack(spacing: 8) {
                    TextField("", value: $thresholdValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .onSubmit {
                            thresholdValue = min(max(thresholdValue, 1), thresholdUnit.maxValue)
                        }
                    Stepper("Value", value: $thresholdValue, in: 1...thresholdUnit.maxValue)
                        .labelsHidden()
                    Text(thresholdUnit.displayName(count: thresholdValue))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Continue") {
                    startScan()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.2)
                .padding(.top, 20)

            Text("Scanning backups...")
                .font(.headline)
        }
        .frame(maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(spacing: 24) {
            Image(systemName: "trash")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text("\(previewCount) backup(s) will be deleted")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Backups older than \(thresholdValue) \(thresholdUnit.displayName(count: thresholdValue))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Delete \(previewCount)") {
                    startDelete()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Deleting

    private var deletingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.2)
                .padding(.top, 20)

            Text("Deleting backups...")
                .font(.headline)

            if !progressText.isEmpty {
                Text(progressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Done

    private func doneView(_ result: BackupViewModel.DeletionResult) -> some View {
        VStack(spacing: 24) {
            Image(systemName: result.failed > 0 ? "exclamationmark.triangle" : "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(result.failed > 0 ? .orange : .green)
                .padding(.top, 12)

            Text(result.failed > 0 ? "Trim completed with errors" : "Trim completed")
                .font(.headline)

            HStack(spacing: 32) {
                VStack(spacing: 2) {
                    Text("\(result.deleted)")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Deleted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if result.failed > 0 {
                    VStack(spacing: 2) {
                        Text("\(result.failed)")
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                        Text("Failed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)

            Button("Done") {
                viewModel.reset()
                dismiss()
            }
            .keyboardShortcut(.return)
        }
        .padding(24)
    }

    // MARK: - Actions

    private func startScan() {
        phase = .scanning

        Task {
            let count = await viewModel.prepareTrimNow(value: thresholdValue, unit: thresholdUnit)
            await MainActor.run {
                if let count, count > 0 {
                    phase = .preview(count: count)
                } else {
                    viewModel.reset()
                    dismiss()
                }
            }
        }
    }

    private func startDelete() {
        phase = .deleting
        progressText = "Deleting backups..."

        Task {
            let result = await viewModel.confirmedTrimNow()
            await MainActor.run {
                if let result {
                    if result.deleted > 0 || result.failed > 0 {
                        SettingsStore.shared.recordTrim(
                            date: Date(),
                            count: result.deleted,
                            space: formatter.string(fromByteCount: result.spaceReclaimed)
                        )
                    }
                    phase = .done(result)
                } else {
                    viewModel.reset()
                    dismiss()
                }
            }
        }
    }
}
