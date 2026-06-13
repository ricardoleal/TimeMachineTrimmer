import Foundation
import UserNotifications

@MainActor
final class AutoTrimService {
    static let shared = AutoTrimService()

    private let service = TMUtilService()
    private var timer: Timer?
    private var isRunning = false
    private var requestedNotifications = false

    func start() {
        if SettingsStore.shared.autoTrimEnabled {
            Task { await runNow() }
        }
        scheduleNextRun()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func runNow() async {
        guard !isRunning else {
            DebugLogger.log("AutoTrim: already running, skipping")
            return
        }
        isRunning = true
        defer {
            isRunning = false
            scheduleNextRun()
        }

        let settings = SettingsStore.shared

        if let lastTrim = settings.autoTrimLastRun,
           Date().timeIntervalSince(lastTrim) < 24 * 3_600 {
            settings.autoTrimLastRun = Date()
            settings.autoTrimResult = "Skipped: less than 24 hours since last trim"
            return
        }

        let toDelete = await findCandidates(settings: settings)
        guard !toDelete.isEmpty else { return }

        await deleteCandidates(toDelete, settings: settings)
    }

    private func findCandidates(settings: SettingsStore) async -> [TimeMachineBackup] {
        DebugLogger.log("AutoTrim: starting scan")
        let destinations = try? await service.getDestinations()
        guard let mountPoint = destinations?.first?.mountPoint else {
            settings.autoTrimLastRun = Date()
            settings.autoTrimResult = "No backup destination found"
            return []
        }

        let backups = (try? await service.listBackups(mountPoint: mountPoint)) ?? []
        let cutoff = settings.autoTrimThresholdUnit.cutoffDate(byAdding: settings.autoTrimThresholdValue)
        let toDelete = backups.filter { $0.date < cutoff }

        if toDelete.isEmpty {
            let label: String = {
                let count = settings.autoTrimThresholdValue
                return "No backups older than \(count) \(settings.autoTrimThresholdUnit.displayName(count: count))"
            }()
            settings.autoTrimLastRun = Date()
            settings.autoTrimResult = label
        }

        DebugLogger.log("AutoTrim: found \(toDelete.count) candidate(s) out of \(backups.count)")
        return toDelete
    }

    private func deleteCandidates(_ toDelete: [TimeMachineBackup], settings: SettingsStore) async {
        DebugLogger.log("AutoTrim: deleting \(toDelete.count) backup(s)")
        let client = HelperClient()
        guard client.isInstalled else {
            settings.autoTrimLastRun = Date()
            settings.autoTrimResult = "Helper not installed"
            return
        }

        do {
            let results = try await client.deleteBackups(toDelete)
            var deleted = 0
            for backup in toDelete {
                if let error = results[backup.id], !error.isEmpty {
                    DebugLogger.log("AutoTrim: failed \(backup.snapshotName ?? backup.id) — \(error)")
                } else {
                    deleted += 1
                }
            }
            SettingsStore.shared.recordTrim(date: Date(), count: deleted, space: "")
            settings.autoTrimLastRun = Date()
            settings.autoTrimResult = "\(deleted) snapshot(s) deleted"
            DebugLogger.log("AutoTrim: done — \(deleted) deleted")

            if settings.trimNotifyOnComplete {
                postNotification(title: "Auto Trim Complete", body: "\(deleted) old backup(s) deleted.")
            }
        } catch {
            DebugLogger.log("AutoTrim: deletion failed — \(error.localizedDescription)")
            settings.autoTrimLastRun = Date()
            settings.autoTrimResult = "Error: \(error.localizedDescription)"
        }
    }

    private func scheduleNextRun() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard SettingsStore.shared.autoTrimEnabled else { return }
                await self?.runNow()
            }
        }
    }

    private func postNotification(title: String, body: String) {
        if !requestedNotifications {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                Task { @MainActor in
                    self.requestedNotifications = true
                    if granted { self.deliverNotification(title: title, body: body) }
                }
            }
        } else {
            deliverNotification(title: title, body: body)
        }
    }

    private func deliverNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
