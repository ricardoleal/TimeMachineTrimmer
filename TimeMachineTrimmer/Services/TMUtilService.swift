import Foundation

actor TMUtilService {

    enum TMError: Error, LocalizedError {
        case processFailed(String)
        case noFDA
        case noDestination
        case backupParsingFailed
        case deleteFailed(String)
        case volumeNotFound(String)
        case notAPFSVolume(String)

        var errorDescription: String? {
            switch self {
            case .processFailed(let msg): return "Command failed: \(msg)"
            case .noFDA: return "Full Disk Access is required"
            case .noDestination: return "No Time Machine destination found"
            case .backupParsingFailed: return "Could not parse backup list"
            case .deleteFailed(let msg): return "Delete failed: \(msg)"
            case .volumeNotFound(let msg): return "Volume not found: \(msg)"
            case .notAPFSVolume(let msg): return "Not an APFS volume: \(msg)"
            }
        }
    }

    @discardableResult
    private func run(_ executable: String, args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let out = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let err = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: out, encoding: .utf8) ?? ""
                let error = String(data: err, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let msg = error.isEmpty ? output : error
                    continuation.resume(throwing: TMError.processFailed(msg))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TMError.processFailed(error.localizedDescription))
            }
        }
    }

    @discardableResult
    private func runPrivileged(_ command: String) async throws -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            process.terminationHandler = { proc in
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: out, encoding: .utf8) ?? ""
                let errorOutput = String(data: errData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let combined = errorOutput.isEmpty ? output : errorOutput
                    if combined.localizedCaseInsensitiveContains("cancelled") ||
                       combined.localizedCaseInsensitiveContains("User canceled") ||
                       combined.localizedCaseInsensitiveContains("(-128)") {
                        continuation.resume(throwing: TMError.processFailed("Authentication cancelled"))
                    } else {
                        continuation.resume(throwing: TMError.processFailed(combined))
                    }
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TMError.processFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - FDA checks

    static func checkFDA() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listbackups"]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            let err = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: err, encoding: .utf8) ?? ""
            let status = process.terminationStatus
            if errorOutput.contains("Full Disk Access") { return false }
            return status == 0
        } catch {
            return false
        }
    }

    static func triggerFDAuthorizationPrompt() {
        let paths = ["/.vol", "/Volumes/.TMExcludeStore"]
        for path in paths {
            _ = FileManager.default.isReadableFile(atPath: path)
            _ = FileManager.default.contents(atPath: path)
        }
    }

    struct BackupStatus {
        let running: Bool
        let firstBackup: Bool
        let phase: String
        let percent: Double
        let timeRemaining: TimeInterval
        let files: Int
        let totalFiles: Int
    }

    static func backupStatus() -> BackupStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["status"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return parseBackupStatus(output)
        } catch {
            return BackupStatus(
                running: false, firstBackup: false,
                phase: "", percent: 0, timeRemaining: 0,
                files: 0, totalFiles: 0
            )
        }
    }

    private static func parseBackupStatus(_ output: String) -> BackupStatus {
        let running = output.contains("Running = 1")
        let firstBackup = output.contains("FirstBackup = 1")
        let phase = extractTMValue(from: output, key: "BackupPhase") ?? ""
        let percent = Double(extractTMValue(from: output, key: "Percent") ?? "") ?? 0
        let timeRemaining = TimeInterval(extractTMValue(from: output, key: "TimeRemaining") ?? "") ?? 0
        let files = Int(extractTMValue(from: output, key: "files") ?? "") ?? 0
        let totalFiles = Int(extractTMValue(from: output, key: "totalFiles") ?? "") ?? 0
        return BackupStatus(
            running: running, firstBackup: firstBackup,
            phase: phase, percent: percent,
            timeRemaining: timeRemaining,
            files: files, totalFiles: totalFiles
        )
    }

    private static func extractTMValue(from output: String, key: String) -> String? {
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key) else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let val = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return val.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: ";", with: "")
        }
        return nil
    }

    // MARK: - Destinations

    func getDestinations() async throws -> [BackupDestination] {
        if let plistDests = readDestinationsFromPlist() {
            return plistDests
        }
        if let snapDests = try? await findDestinationsViaAPFSSnapshots() {
            return snapDests
        }
        throw TMError.noDestination
    }

    /// Quick plist-only lookup — no disk scanning, shows configured destinations immediately
    nonisolated func getConfiguredDestinations() -> [BackupDestination] {
        readDestinationsFromPlist() ?? []
    }

    nonisolated private func readDestinationsFromPlist() -> [BackupDestination]? {
        let path = "/Library/Preferences/com.apple.TimeMachine.plist"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return nil }

        let allDests: [[String: Any]]
        if let known = dict["Destinations"] as? [[String: Any]] {
            allDests = known
        } else if let single = dict["CurrentDestination"] as? [String: Any] {
            allDests = [single]
        } else {
            return nil
        }

        let mounted = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []

        let result = allDests.compactMap { entry -> BackupDestination? in
            let id = (entry["SnapshotDiskUUID"] as? String) ?? (entry["ID"] as? String) ?? UUID().uuidString
            let name = (entry["Name"] as? String) ?? (entry["VolumeName"] as? String) ?? "Time Machine"
            let kind = entry["Kind"] as? String ?? "Local"

            // Try MountPoint from plist first
            if let mountPoint = (entry["MountPoint"] as? String) ?? (entry["mountPoint"] as? String),
               !mountPoint.isEmpty {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: mountPoint, isDirectory: &isDir), isDir.boolValue {
                    return BackupDestination(id: id, name: name, kind: kind, mountPoint: mountPoint)
                }
            }

            // Fallback: match by volume name in /Volumes
            let volName = (entry["VolumeName"] as? String) ?? name
            if let match = mounted.first(where: { $0 == volName }) {
                return BackupDestination(id: id, name: name, kind: kind, mountPoint: "/Volumes/\(match)")
            }

            return nil
        }
        return result.isEmpty ? nil : result
    }

    private func findDestinationsViaAPFSSnapshots() async throws -> [BackupDestination]? {
        let skip = Set(["Update", "Recovery", "Preboot", "VM", "Macintosh HD", "com.apple.TimeMachine.localsnapshots"])
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") else { return nil }
        var result: [BackupDestination] = []
        for item in contents {
            guard !skip.contains(item), !item.hasPrefix(".") else { continue }
            let volPath = "/Volumes/\(item)"

            let snapshotOutput = try? await run(
                "/usr/sbin/diskutil",
                args: ["apfs", "listSnapshots", "-plist", volPath]
            )
            guard let output = snapshotOutput else { continue }

            // Valid APFS volume with Time Machine snapshots
            if output.contains("com.apple.TimeMachine.") {
                result.append(BackupDestination(id: UUID().uuidString, name: item, kind: "APFS", mountPoint: volPath))
            }
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - List Backups

    func listBackups(mountPoint: String) async throws -> [TimeMachineBackup] {
        var backups = try await listBackupsViaAPFS(mountPoint: mountPoint)
        let hasFDA = TMUtilService.checkFDA()
        if hasFDA, let tmutilPaths = try? await listTmutilPaths(mountPoint: mountPoint) {
            for index in backups.indices {
                if let match = tmutilPaths.first(where: { abs($0.date.timeIntervalSince(backups[index].date)) < 120 }) {
                    backups[index] = TimeMachineBackup(
                        id: backups[index].id,
                        date: backups[index].date,
                        path: match.path,
                        volumeName: backups[index].volumeName,
                        snapshotName: backups[index].snapshotName,
                        volumePath: backups[index].volumePath
                    )
                }
            }
        }
        return backups
    }

    private func listTmutilPaths(mountPoint: String) async throws -> [(path: String, date: Date)] {
        let output = try await run("/usr/bin/tmutil", args: ["listbackups", "-d", mountPoint])
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let result = lines.compactMap { line -> (String, Date)? in
            let url = URL(fileURLWithPath: line)
            let name = url.lastPathComponent
            guard let date = parseBackupDate(from: name) else { return nil }
            return (line, date)
        }
        return result
    }

    private func listBackupsViaAPFS(mountPoint: String) async throws -> [TimeMachineBackup] {
        let output = try await run("/usr/sbin/diskutil", args: ["apfs", "listSnapshots", "-plist", mountPoint])
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let snapshots = plist["Snapshots"] as? [[String: Any]] else {
            throw TMError.backupParsingFailed
        }

        let volumeName = URL(fileURLWithPath: mountPoint).lastPathComponent

        let result = snapshots.compactMap { entry -> TimeMachineBackup? in
            guard let name = (entry["SnapshotName"] as? String) ?? (entry["Name"] as? String),
                  name.hasPrefix("com.apple.TimeMachine."),
                  let date = parseBackupDate(from: name) else { return nil }
            return TimeMachineBackup(
                id: name,
                date: date,
                path: "",
                volumeName: volumeName,
                snapshotName: name,
                volumePath: mountPoint
            )
        }
        return result.sorted { $0.date > $1.date }
    }

    // MARK: - Volume Info

    struct VolumeInfo {
        let totalBytes: Int64
        let usedBytes: Int64
        let freeBytes: Int64
        let filesystem: String
        let deviceNode: String
        let solidState: Bool
        let volumeKind: String
    }

    func getVolumeInfo(mountPoint: String) async -> VolumeInfo? {
        guard let output = try? await run("/usr/sbin/diskutil", args: ["info", "-plist", mountPoint]),
              let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let fileSystem = plist["FilesystemType"] as? String ?? plist["FilesystemName"] as? String ?? "?"
        let devNode = plist["DeviceNode"] as? String ?? "?"
        let ssd = plist["SolidState"] as? Bool ?? false
        let kind = plist["VolumeKind"] as? String ?? "?"

        let containerSize = plist["APFSContainerSize"] as? Int64 ?? 0
        let containerFree = plist["APFSContainerFree"] as? Int64 ?? 0
        let capacityInUse = plist["CapacityInUse"] as? Int64 ?? 0
        let freeSpace = plist["FreeSpace"] as? Int64 ?? 0

        var totalBytes: Int64 = 0
        var usedBytes: Int64 = 0
        var freeBytes: Int64 = 0

        if containerSize > 0, containerFree > 0 {
            totalBytes = containerSize
            usedBytes = containerSize - containerFree
            freeBytes = containerFree
        } else if capacityInUse > 0 || freeSpace > 0 {
            totalBytes = capacityInUse + freeSpace
            usedBytes = capacityInUse
            freeBytes = freeSpace
        }

        return VolumeInfo(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            freeBytes: freeBytes,
            filesystem: fileSystem,
            deviceNode: devNode,
            solidState: ssd,
            volumeKind: kind
        )
    }

    // MARK: - Delete

    func deleteBackup(_ backup: TimeMachineBackup) async throws {
        guard let mountPoint = backup.volumePath,
              let snapshotName = backup.snapshotName else {
            throw TMError.backupParsingFailed
        }

        let escapedMount = mountPoint.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedName = snapshotName.replacingOccurrences(of: "\"", with: "\\\"")
        let command = "/usr/bin/tmutil deletebackups -d \"\(escapedMount)\" -t \"\(escapedName)\""

        do {
            try await runPrivileged(command)
        } catch let error as TMError {
            if case .processFailed(let raw) = error {
                let errorCode = parseErrorCode(raw)
                let codePrefix = errorCode.map { "Error \($0): " } ?? ""
                throw TMError.deleteFailed("\(codePrefix)\(raw)")
            }
            throw error
        }
    }

    /// Extracts numeric error codes (e.g. -69528) from osascript/command output
    private func parseErrorCode(_ output: String) -> String? {
        let patterns = [
            #"Error:\s*(-\d+)"#,
            #"\((-?\d+)\)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                  match.numberOfRanges >= 2 else { continue }
            let nsStr = output as NSString
            return nsStr.substring(with: match.range(at: 1))
        }
        return nil
    }

    // MARK: - Date parsing

    private func parseBackupDate(from name: String) -> Date? {
        let patterns = [
            #"^(\d{4})-(\d{2})-(\d{2})-(\d{6})(\.backup)?$"#,
            #"\.(\d{4})-(\d{2})-(\d{2})-(\d{6})"#
        ]
        for pattern in patterns {
            if let date = parseDateWithPattern(pattern, in: name) { return date }
        }
        return nil
    }

    private func parseDateWithPattern(_ pattern: String, in name: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              match.numberOfRanges >= 5 else { return nil }
        let nsName = name as NSString
        let yearStr = nsName.substring(with: match.range(at: 1))
        let monthStr = nsName.substring(with: match.range(at: 2))
        let dayStr = nsName.substring(with: match.range(at: 3))
        let timeStr = nsName.substring(with: match.range(at: 4))
        var dateComponents = DateComponents()
        dateComponents.year = Int(yearStr)
        dateComponents.month = Int(monthStr)
        dateComponents.day = Int(dayStr)
        dateComponents.hour = Int(String(timeStr.prefix(2)))
        dateComponents.minute = Int(String(timeStr.dropFirst(2).prefix(2)))
        dateComponents.second = Int(String(timeStr.dropFirst(4).prefix(2)))
        return Calendar.current.date(from: dateComponents)
    }
}
