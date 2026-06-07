import SwiftUI

struct PreviewSheet: View {
    @Environment(BackupViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showConfirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            listSection
            Divider()
            footer
        }
        .frame(width: 600, height: 480)
        .alert("Permanently Delete Backups?", isPresented: $showConfirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(viewModel.previewBackups.count) Backups", role: .destructive) {
                dismiss()
                Task { await viewModel.executeDeletion() }
            }
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        let count = viewModel.previewBackups.count
        let suffix = count == 1 ? "" : "s"
        return "This will permanently delete \(count) backup\(suffix).\n\n"
            + "This action cannot be undone — deleted APFS snapshots cannot be recovered."
    }

    private var header: some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(Color.actionCoral)
                .padding(.top, 16)
            Text("Review Backups to Delete")
                .font(.title3)
                .fontWeight(.semibold)
            Text("This action cannot be undone. Time Machine does not support undo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 12)
    }

    private var listSection: some View {
        BackupListView(backups: viewModel.previewBackups)
            .padding()
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if viewModel.tmBackupRunning {
                Label("Time Machine is backing up — deletion may fail.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.actionCoral)
                    .font(.caption)
            }

            HStack {
                Text("\(viewModel.previewBackups.count) backups")
                    .font(.headline)
                Spacer()
                Button("Cancel", role: .cancel) {
                    viewModel.state = .scanned
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Delete \(viewModel.previewBackups.count) Backups", role: .destructive) {
                    showConfirmDelete = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.actionCoral)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}
