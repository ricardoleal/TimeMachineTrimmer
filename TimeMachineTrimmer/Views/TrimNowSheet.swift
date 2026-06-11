import SwiftUI

private enum TrimPhase {
    case configure
    case running
    case done(BackupViewModel.DeletionResult)
}

struct TrimNowSheet: View {
    @Environment(BackupViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var phase: TrimPhase = .configure
    @State private var threshold: Int = SettingsStore.shared.ageThresholdMonths
    @State private var progressText: String = ""

    private let formatter = ByteCountFormatter()

    private var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    var body: some View {
        VStack(spacing: 20) {
            switch phase {
            case .configure:
                configureView
            case .running:
                runningView
            case .done(let result):
                doneView(result)
            }
        }
        .frame(width: 380)
        .padding(24)
        .interactiveDismissDisabled(isRunning)
        .onDisappear {
            viewModel.isTrimNowActive = false
        }
    }

    // MARK: - Configure

    private var configureView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title)
                .foregroundStyle(.secondary)

            Text("Trim Backups")
                .font(.headline)

            Text("Delete snapshots older than \(threshold) months")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("1")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Slider(value: Binding(
                    get: { Double(threshold) },
                    set: { threshold = Int($0) }
                ), in: 1...24, step: 1)
                Text("24")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text("\(threshold) months")
                .font(.title3)
                .fontWeight(.medium)
                .monospacedDigit()
                .contentTransition(.numericText())

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)

                Button("Trim") {
                    startTrim()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Running

    private var runningView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Trimming backups...")
                .font(.headline)

            if !progressText.isEmpty {
                Text(progressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Done

    private func doneView(_ result: BackupViewModel.DeletionResult) -> some View {
        VStack(spacing: 20) {
            Image(systemName: result.failed > 0 ? "exclamationmark.triangle" : "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(result.failed > 0 ? .orange : .green)

            Text(result.failed > 0 ? "Trim completed with errors" : "Trim completed")
                .font(.headline)

            HStack(spacing: 24) {
                VStack {
                    Text("\(result.deleted)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Deleted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if result.failed > 0 {
                    VStack {
                        Text("\(result.failed)")
                            .font(.title2)
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
            .padding(.top, 4)
        }
    }

    // MARK: - Actions

    private func startTrim() {
        phase = .running
        progressText = "Scanning backups..."

        Task {
            let result = await viewModel.quickTrimNow(thresholdMonths: threshold)
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
                    progressText = "No backups to trim"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        viewModel.reset()
                        dismiss()
                    }
                }
            }
        }
    }
}
