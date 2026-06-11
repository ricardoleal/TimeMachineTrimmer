import SwiftUI

@MainActor
@Observable
final class BackupViewModel {

    enum TrimMethod: String, CaseIterable, Identifiable {
        case age = "By Age"
        case manual = "Manual"
        var id: Self { self }
    }

    struct DeletionError: Identifiable, Equatable {
        let id = UUID()
        let backup: TimeMachineBackup
        let error: String
    }

    struct DeletionResult: Equatable {
        let deleted: Int
        let failed: Int
        let spaceReclaimed: Int64
        let errors: [DeletionError]
    }

    enum AppState: Equatable {
        case ready
        case scanning
        case scanned
        case previewing
        case deleting
        case done(DeletionResult)
        case error(String)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.ready, .ready), (.scanning, .scanning),
                 (.scanned, .scanned), (.previewing, .previewing), (.deleting, .deleting):
                return true
            case let (.done(lhsResult), .done(rhsResult)): return lhsResult == rhsResult
            case let (.error(lhsMsg), .error(rhsMsg)): return lhsMsg == rhsMsg
            default: return false
            }
        }
    }

    private let service = TMUtilService()
    private var statusPollTask: Task<Void, Never>?

    func startStatusPolling() {
        pollStatus()
        statusPollTask?.cancel()
        statusPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { self?.pollStatus() }
            }
        }
    }

    private func pollStatus() {
        let status = TMFDAUtils.backupStatus()
        tmBackupRunning = status.running
        backupProgress = status.percent
        backupTimeRemaining = status.timeRemaining
        backupPhase = status.phase
        backupFiles = status.files
        backupTotalFiles = status.totalFiles
    }

    var state: AppState = .ready
    var needsPermissionSheet: Bool = false
    var destinations: [BackupDestination] = []
    var backups: [TimeMachineBackup] = []
    var volumeInfo: TMUtilTypes.VolumeInfo?
    var selectedMethod: TrimMethod = .age {
        didSet { if selectedMethod == .age { updateAgeSelection() } }
    }
    var ageThresholdMonths: Int = 6 {
        didSet { if selectedMethod == .age { updateAgeSelection() } }
    }
    var previewBackups: [TimeMachineBackup] = []
    var selectedBackupIds: Set<String> = []
    var deletionProgress: Double = 0
    var deletionLog: [String] = []
    var isBatchDeletion: Bool = false
    var errorMessage: String?
    var searchQuery: String = ""
    var tmBackupRunning: Bool = false
    var backupProgress: Double = 0
    var backupTimeRemaining: TimeInterval = 0
    var backupPhase: String = ""
    var backupFiles: Int = 0
    var backupTotalFiles: Int = 0
    var isTrimNowActive: Bool = false

    var filteredBackups: [TimeMachineBackup] {
        guard !searchQuery.isEmpty else { return backups }
        return backups.filter { backup in
            backup.volumeName.localizedCaseInsensitiveContains(searchQuery) ||
            backup.dateFormatted.localizedCaseInsensitiveContains(searchQuery) ||
            backup.dateShortFormatted.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var totalBackupSize: Int64 {
        volumeInfo?.usedBytes ?? 0
    }

    var oldestBackupDate: Date? {
        backups.map(\.date).min()
    }

    var newestBackupDate: Date? {
        backups.map(\.date).max()
    }

    var oldestDateFormatted: String {
        oldestBackupDate?.formatted(date: .numeric, time: .omitted) ?? "\u{2014}"
    }

    var newestDateFormatted: String {
        newestBackupDate?.formatted(date: .numeric, time: .omitted) ?? "\u{2014}"
    }

    var selectedDestination: BackupDestination? {
        get { _selectedDestination ?? destinations.first }
        set { _selectedDestination = newValue }
    }
    var _selectedDestination: BackupDestination?

    var totalSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBackupSize)
    }

    func requestPermissions() {
        DebugLogger.log("requestPermissions: opening System Settings FDA page")
        needsPermissionSheet = true
        TMFDAUtils.triggerFDAuthorizationPrompt()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    func dismissPermissions() {
        needsPermissionSheet = false
    }

    func checkPermissionsAndScan() async {
        DebugLogger.log("checkPermissionsAndScan")
        if !TMFDAUtils.checkFDA() {
            DebugLogger.log("checkPermissionsAndScan: FDA denied, showing permission sheet")
            needsPermissionSheet = true
            return
        }
        DebugLogger.log("checkPermissionsAndScan: FDA granted, scanning")
        needsPermissionSheet = false
        await scanBackups()
    }

    /// Load known destinations from Time Machine plist (fast, no disk scanning)
    func loadDestinations() {
        destinations = service.getConfiguredDestinations()
        DebugLogger.log("loadDestinations: \(destinations.count) destinations")
    }

    func selectFirstDestination() {
        _selectedDestination = destinations.first
        DebugLogger.log("selectFirstDestination: \(_selectedDestination?.name ?? "nil")")
    }

    func selectDestination(_ destination: BackupDestination) async {
        DebugLogger.log("selectDestination: \(destination.name) (\(destination.mountPoint ?? "nil"))")
        _selectedDestination = destination
        selectedBackupIds.removeAll()
        await scanBackups()
    }

    var destinationLabel: String {
        guard let dest = selectedDestination else { return "Select Destination" }
        return dest.name
    }

    func scanBackups() async {
        DebugLogger.log("scanBackups: starting")
        state = .scanning
        needsPermissionSheet = false
        tmBackupRunning = TMFDAUtils.backupStatus().running
        do {
            destinations = try await service.getDestinations()
            guard let mountPoint = selectedDestination?.mountPoint else {
                DebugLogger.log("scanBackups: no mount point, showing error")
                state = .error(
                    "No Time Machine destination volume found.\n"
                    + "Connect your Time Machine drive and try again."
                )
                return
            }
            DebugLogger.log("scanBackups: mountPoint=\(mountPoint)")
            backups = try await service.listBackups(mountPoint: mountPoint)
            volumeInfo = await service.getVolumeInfo(mountPoint: mountPoint)
            if selectedMethod == .age { updateAgeSelection() }
            DebugLogger.log("scanBackups: done — \(backups.count) backups")
            state = .scanned
        } catch {
            DebugLogger.log("scanBackups: error — \(error.localizedDescription)")
            state = .error(error.localizedDescription)
        }
    }

    func computePreview() {
        previewBackups = backups.filter { selectedBackupIds.contains($0.id) }
        state = .previewing
    }

    func updateAgeSelection() {
        let cutoff = Calendar.current.date(
            byAdding: .month,
            value: -ageThresholdMonths,
            to: Date()
        ) ?? Date()
        selectedBackupIds = Set(backups.filter { $0.date < cutoff }.map(\.id))
    }

    func executeDeletion() async {
        DebugLogger.log("executeDeletion: starting — \(previewBackups.count) backups")
        state = .deleting
        deletionProgress = 0
        deletionLog = []

        // Try helper batch first
        let helperClient = HelperClient()
        if await helperClient.isInstalled {
            isBatchDeletion = true
            deletionLog.append("Sending \(previewBackups.count) backup(s) to privileged helper...")
            do {
                let results = try await service.deleteBackupsViaHelper(previewBackups)
                await processHelperResults(results)
                return
            } catch {
                DebugLogger.log(
                    "executeDeletion: helper failed, falling back to legacy — \(error.localizedDescription)"
                )
            }
        }

        // Fallback: per-backup loop
        await executeLegacyDeletion()
    }

    private func processHelperResults(_ results: [String: String]) async {
        isBatchDeletion = false
        var deleted = 0
        var failed = 0
        var errors: [DeletionError] = []
        var deletedIds: Set<String> = []

        for backup in previewBackups {
            if let error = results[backup.id], !error.isEmpty {
                failed += 1
                DebugLogger.log("executeDeletion: ❌ \(backup.snapshotName ?? backup.id) — \(error)")
                errors.append(DeletionError(backup: backup, error: error))
                deletionLog.append("\u{274C} \(backup.dateShortFormatted): \(error)")
            } else {
                deleted += 1
                deletedIds.insert(backup.id)
                DebugLogger.log("executeDeletion: ✅ \(backup.snapshotName ?? backup.id)")
                deletionLog.append("\u{2705} \(backup.dateShortFormatted): Deleted")
            }
        }

        deletionProgress = 1.0
        backups.removeAll { deletedIds.contains($0.id) }
        selectedBackupIds.subtract(deletedIds)

        let result = DeletionResult(
            deleted: deleted,
            failed: failed,
            spaceReclaimed: 0,
            errors: errors
        )
        DebugLogger.log("executeDeletion: done — \(deleted) deleted, \(failed) failed")
        if deleted > 0 {
            SettingsStore.shared.recordTrim(date: Date(), count: deleted, space: "")
        }
        state = .done(result)
    }

    private func executeLegacyDeletion() async {
        let total = Double(previewBackups.count)
        var deleted = 0
        var failed = 0
        var errors: [DeletionError] = []
        var deletedIds: Set<String> = []

        for (index, backup) in previewBackups.enumerated() {
            do {
                try await service.deleteBackup(backup)
                deleted += 1
                deletedIds.insert(backup.id)
                DebugLogger.log("executeDeletion: ✅ \(backup.snapshotName ?? backup.id)")
                deletionLog.append("\u{2705} \(backup.dateShortFormatted): Deleted")
            } catch {
                failed += 1
                let msg = error.localizedDescription
                DebugLogger.log("executeDeletion: ❌ \(backup.snapshotName ?? backup.id) — \(msg)")
                errors.append(DeletionError(backup: backup, error: msg))
                deletionLog.append("\u{274C} \(backup.dateShortFormatted): \(msg)")
            }
            deletionProgress = Double(index + 1) / total
        }

        backups.removeAll { deletedIds.contains($0.id) }
        selectedBackupIds.subtract(deletedIds)

        let result = DeletionResult(
            deleted: deleted,
            failed: failed,
            spaceReclaimed: 0,
            errors: errors
        )
        DebugLogger.log("executeDeletion: done — \(deleted) deleted, \(failed) failed")
        if deleted > 0 {
            SettingsStore.shared.recordTrim(date: Date(), count: deleted, space: "")
        }
        state = .done(result)
    }

    func reset() {
        state = .ready
        previewBackups = []
        selectedBackupIds = []
        deletionProgress = 0
        deletionLog = []
        isBatchDeletion = false
        isTrimNowActive = false
    }

    func toggleBackupSelection(_ id: String) {
        if selectedBackupIds.contains(id) {
            selectedBackupIds.remove(id)
        } else {
            selectedBackupIds.insert(id)
        }
    }

    func selectAllBackups() {
        selectedBackupIds = Set(backups.map(\.id))
    }

    func deselectAllBackups() {
        selectedBackupIds.removeAll()
    }

    func quickTrimNow(thresholdMonths: Int) async -> DeletionResult? {
        DebugLogger.log("quickTrimNow: threshold=\(thresholdMonths)")
        isTrimNowActive = true
        ageThresholdMonths = thresholdMonths
        selectedMethod = .age

        if !TMFDAUtils.checkFDA() {
            needsPermissionSheet = true
            isTrimNowActive = false
            return nil
        }

        await scanBackups()
        guard state == .scanned else {
            isTrimNowActive = false
            return nil
        }

        updateAgeSelection()

        guard !selectedBackupIds.isEmpty else {
            DebugLogger.log("quickTrimNow: no backups match threshold")
            isTrimNowActive = false
            return nil
        }

        previewBackups = backups.filter { selectedBackupIds.contains($0.id) }
        await executeDeletion()

        guard case .done(let result) = state else {
            isTrimNowActive = false
            return nil
        }

        return result
    }
}
