import SwiftUI

struct DashboardView: View {
    @Environment(BackupViewModel.self) private var viewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if viewModel.backups.isEmpty { emptyState } else { contentBody }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("focusSearch"))) { _ in
            isSearchFocused = true
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if !viewModel.destinations.isEmpty {
                destinationPicker
                diskInfoBar
                backupStatusIndicator
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.questionmark")
                        .foregroundStyle(.tertiary)
                    Text("Click Scan to detect Time Machine destinations")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if !viewModel.backups.isEmpty {
                searchField
            }

            Button("Scan", systemImage: "arrow.clockwise") {
                if viewModel.selectedDestination == nil {
                    viewModel.selectFirstDestination()
                }
                Task { await viewModel.checkPermissionsAndScan() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.state == .scanning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(height: 52)
        .background(.regularMaterial)
    }

    private var destinationPicker: some View {
        Menu {
            ForEach(viewModel.destinations) { dest in
                Button {
                    Task { await viewModel.selectDestination(dest) }
                } label: {
                    HStack {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(Color.actionCoral)
                        Text(dest.name)
                        if dest.id == viewModel.selectedDestination?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentTeal)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(Color.accentTeal)
                Text(viewModel.destinationLabel)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var diskInfoBar: some View {
        if let info = viewModel.volumeInfo, viewModel.selectedDestination != nil {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: info.solidState ? "bolt.fill" : "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(info.solidState ? .blue : .secondary)
                    Text("\(info.filesystem.uppercased()) • \(info.deviceNode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                let fraction = info.totalBytes > 0 ? CGFloat(info.usedBytes) / CGFloat(info.totalBytes) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.fill.quaternary)
                        .frame(width: 80, height: 5)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.actionCoral.opacity(0.7))
                        .frame(width: max(0, min(80, 80 * fraction)), height: 5)
                }

                Text(ByteCountFormatter.formatBytes(info.freeBytes))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var backupStatusIndicator: some View {
        HStack(spacing: 5) {
            if viewModel.tmBackupRunning {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(Color.actionCoral)
                HStack(spacing: 2) {
                    Text("Backing up…")
                        .font(.caption)
                        .foregroundStyle(Color.actionCoral)
                    if viewModel.backupTimeRemaining > 0 {
                        Text(verbatim: etaString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var etaString: String {
        let totalSeconds = Int(viewModel.backupTimeRemaining)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m remaining" }
        return "\(minutes)m remaining"
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .imageScale(.small)

            TextField("Filter backups…", text: Bindable(viewModel).searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isSearchFocused)

            if !viewModel.searchQuery.isEmpty {
                Button("", systemImage: "xmark.circle.fill") {
                    viewModel.searchQuery = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 160, idealWidth: 240, maxWidth: 360)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
        .animation(.easeOut(duration: 0.15), value: viewModel.searchQuery)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Group {
            if viewModel.tmBackupRunning && !viewModel.destinations.isEmpty {
                ContentUnavailableView(
                    "First Backup in Progress",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text(
                        "Time Machine is completing its first backup to this disk. "
                        + "No backups available to trim yet — check back once the backup finishes."
                    )
                )
            } else if viewModel.state == .ready && !viewModel.destinations.isEmpty {
                ContentUnavailableView(
                    "Select a Destination",
                    systemImage: "externaldrive.badge.timemachine",
                    description: Text("Pick a Time Machine volume from the top bar and click Scan.")
                )
            } else {
                ContentUnavailableView(
                    "No Backups Found",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text("Connect your Time Machine drive and click Scan.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private var contentBody: some View {
        VStack(spacing: 0) {
            statsBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            backupTable
                .padding(.horizontal, 20)
                .layoutPriority(1)

            trimSection
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 24) {
            StatItem(icon: "externaldrive", value: "\(viewModel.filteredBackups.count)", label: "backups")
            if let info = viewModel.volumeInfo {
                Divider()
                    .frame(height: 16)
                StatItem(
                    icon: "internaldrive",
                    value: ByteCountFormatter.formatBytes(info.usedBytes),
                    label: "used"
                )
                StatItem(
                    icon: "externaldrive.badge.checkmark",
                    value: ByteCountFormatter.formatBytes(info.freeBytes),
                    label: "free"
                )
                StatItem(
                    icon: "archivebox",
                    value: ByteCountFormatter.formatBytes(info.totalBytes),
                    label: "total"
                )
            }
            Divider()
                .frame(height: 16)
            StatItem(icon: "calendar", value: viewModel.oldestDateFormatted, label: "oldest")
            StatItem(icon: "calendar", value: viewModel.newestDateFormatted, label: "newest")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Backup Table

    private var backupTable: some View {
        BackupListView(
            backups: viewModel.filteredBackups,
            selection: Bindable(viewModel).selectedBackupIds
        )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 0.5)
            )
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
            .frame(minHeight: 120)
            .animation(.easeOut(duration: 0.15), value: viewModel.searchQuery)
    }

    // MARK: - Trim Section

    private var trimSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "scissors")
                        .foregroundStyle(Color.actionCoral)
                    Text("Trim Backups")
                        .font(.headline)
                }
                Spacer()

                Picker("", selection: Bindable(viewModel).selectedMethod) {
                    ForEach(BackupViewModel.TrimMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Group {
                switch viewModel.selectedMethod {
                case .age: TrimByAgeView()
                case .manual: TrimManualView()
                }
            }

            HStack {
                if viewModel.tmBackupRunning {
                    Label("Time Machine is running — selection may be stale.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.actionCoral)
                        .font(.caption)
                }
                Spacer()
                Text("\(viewModel.selectedBackupIds.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Button("Preview Deletion") {
                    viewModel.computePreview()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.accentTeal)
                .disabled(viewModel.selectedBackupIds.isEmpty)
            }
        }
        .padding(16)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(.tertiary)
                .imageScale(.small)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(label)
                .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
    }
}
