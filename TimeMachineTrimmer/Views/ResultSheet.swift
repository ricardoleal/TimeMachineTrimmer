import SwiftUI

struct ResultSheet: View {
    @Environment(BackupViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if case .done(let result) = viewModel.state {
                Image(systemName: result.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(result.failed == 0 ? Color.accentTeal : Color.actionCoral)

                Text(result.failed == 0 ? "Deletion Complete" : "Completed with Errors")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(spacing: 6) {
                    ResultRow(label: "Successfully deleted", value: "\(result.deleted)")
                    ResultRow(label: "Failed", value: "\(result.failed)")
                }
                .padding(.horizontal)

                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Errors")
                                .font(.headline)
                            Spacer()
                            Button("Copy All") {
                                copyToClipboard(result.errors.map { "\($0.backup.dateShortFormatted): \($0.error)" }.joined(separator: "\n"))
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.tint)
                        }
                        .padding(.bottom, 2)
                        ForEach(result.errors) { item in
                            HStack(alignment: .top, spacing: 4) {
                                Text("\(item.backup.dateShortFormatted): \(item.error)")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                                Button {
                                    copyToClipboard("\(item.backup.dateShortFormatted): \(item.error)")
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tertiary)
                                .onHover { hovering in
                                    if hovering { NSCursor.pointingHand.push() }
                                    else { NSCursor.pop() }
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                }
            } else {
                ProgressView()
            }

            Spacer()

            Button("Done") {
                viewModel.reset()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return)
            .padding(.bottom)
        }
        .frame(width: 420, height: 380)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ResultRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}
