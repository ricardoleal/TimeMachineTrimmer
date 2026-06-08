import Foundation

actor TMUtilService {

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
                    continuation.resume(throwing: TMUtilTypes.TMError.processFailed(msg))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TMUtilTypes.TMError.processFailed(error.localizedDescription))
            }
        }
    }

    @discardableResult
    private func runPrivileged(_ command: String) async throws -> String {
        DebugLogger.log("runPrivileged: \(command.prefix(200))")
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
                        continuation.resume(throwing: TMUtilTypes.TMError.processFailed("Authentication cancelled"))
                    } else {
                        continuation.resume(throwing: TMUtilTypes.TMError.processFailed(combined))
                    }
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: TMUtilTypes.TMError.processFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Destinations

    func getDestinations() async throws -> [BackupDestination] {
        if let plistDests = readDestinationsFromPlist() {
            DebugLogger.log("getDestinations: found \(plistDests.count) via plist")
            return plistDests
        }
        DebugLogger.log("getDestinations: plist returned nil, trying APFS scan")
        if let snapDests = try? await findDestinationsViaAPFSSnapshots() {
            DebugLogger.log("getDestinations: found \(snapDests.count) via APFS scan")
            return snapDests
        }
        DebugLogger.log("getDestinations: no destinations found, throwing noDestination")
        throw TMUtilTypes.TMError.noDestination
    }

    /// Quick plist-only lookup — no disk scanning, shows configured destinations immediately
    nonisolated func getConfiguredDestinations() -> [BackupDestination] {
        let dests = readDestinationsFromPlist() ?? []
        DebugLogger.log("getConfiguredDestinations: \(dests.count) destinations")
        return dests
    }

    nonisolated private func readDestinationsFromPlist() -> [BackupDestination]? {
        let path = "/Library/Preferences/com.apple.TimeMachine.plist"
        guard let data = FileManager.default.contents(atPath: path) else {
            DebugLogger.log("readDestinationsFromPlist: plist not readable (no FDA?)")
            return nil
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else {
            DebugLogger.log("readDestinationsFromPlist: plist read but parse failed")
            return nil
        }

        let allDests: [[String: Any]]
        if let known = dict["Destinations"] as? [[String: Any]] {
            allDests = known
        } else if let single = dict["CurrentDestination"] as? [String: Any] {
            allDests = [single]
        } else {
            DebugLogger.log("readDestinationsFromPlist: no Destinations or CurrentDestination key")
            return nil
        }

        let mounted = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
        DebugLogger.log("readDestinationsFromPlist: \(allDests.count) configured, mounted: \(mounted)")

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
        DebugLogger.log("readDestinationsFromPlist: \(result.count) destinations resolved")
        return result.isEmpty ? nil : result
    }

    private func findDestinationsViaAPFSSnapshots() async throws -> [BackupDestination]? {
        let skip = Set(["Update", "Recovery", "Preboot", "VM", "Macintosh HD", "com.apple.TimeMachine.localsnapshots"])
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") else {
            DebugLogger.log("findDestinationsViaAPFSSnapshots: /Volumes not readable")
            return nil
        }
        DebugLogger.log("findDestinationsViaAPFSSnapshots: scanning \(contents)")
        var result: [BackupDestination] = []
        for item in contents {
            guard !skip.contains(item), !item.hasPrefix(".") else { continue }
            let volPath = "/Volumes/\(item)"

            let snapshotOutput = try? await run(
                "/usr/sbin/diskutil",
                args: ["apfs", "listSnapshots", "-plist", volPath]
            )
            guard let output = snapshotOutput else {
                DebugLogger.log("findDestinationsViaAPFSSnapshots: \(item) → diskutil failed")
                continue
            }

            // Valid APFS volume with Time Machine snapshots
            if output.contains("com.apple.TimeMachine.") {
                DebugLogger.log("findDestinationsViaAPFSSnapshots: \(item) → has TM snapshots ✓")
                result.append(BackupDestination(id: UUID().uuidString, name: item, kind: "APFS", mountPoint: volPath))
            } else {
                DebugLogger.log("findDestinationsViaAPFSSnapshots: \(item) → no TM snapshots")
            }
        }
        DebugLogger.log("findDestinationsViaAPFSSnapshots: \(result.count) destinations found")
        return result.isEmpty ? nil : result
    }

    // MARK: - List Backups

    func listBackups(mountPoint: String) async throws -> [TimeMachineBackup] {
        var backups = try await listBackupsViaAPFS(mountPoint: mountPoint)
        DebugLogger.log("listBackups: \(backups.count) via APFS on \(mountPoint)")
        let hasFDA = TMFDAUtils.checkFDA()
        if hasFDA, let tmutilPaths = try? await listTmutilPaths(mountPoint: mountPoint) {
            DebugLogger.log("listBackups: \(tmutilPaths.count) tmutil paths, merging paths")
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
        } else {
            DebugLogger.log("listBackups: no tmutil paths (FDA=\(hasFDA))")
        }
        DebugLogger.log("listBackups: returning \(backups.count) backups")
        return backups
    }

    private func listTmutilPaths(mountPoint: String) async throws -> [(path: String, date: Date)] {
        let output = try await run("/usr/bin/tmutil", args: ["listbackups", "-d", mountPoint])
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let result = lines.compactMap { line -> (String, Date)? in
            let url = URL(fileURLWithPath: line)
            let name = url.lastPathComponent
            guard let date = TMUtilTypes.parseBackupDate(from: name) else { return nil }
            return (line, date)
        }
        DebugLogger.log("listTmutilPaths: \(result.count) paths parsed on \(mountPoint)")
        return result
    }

    private func listBackupsViaAPFS(mountPoint: String) async throws -> [TimeMachineBackup] {
        let output = try await run("/usr/sbin/diskutil", args: ["apfs", "listSnapshots", "-plist", mountPoint])
        guard let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let snapshots = plist["Snapshots"] as? [[String: Any]] else {
            DebugLogger.log("listBackupsViaAPFS: parse failed for \(mountPoint)")
            throw TMUtilTypes.TMError.backupParsingFailed
        }

        let volumeName = URL(fileURLWithPath: mountPoint).lastPathComponent

        let result = snapshots.compactMap { entry -> TimeMachineBackup? in
            guard let name = (entry["SnapshotName"] as? String) ?? (entry["Name"] as? String),
                  name.hasPrefix("com.apple.TimeMachine."),
                  let date = TMUtilTypes.parseBackupDate(from: name) else { return nil }
            return TimeMachineBackup(
                id: name,
                date: date,
                path: "",
                volumeName: volumeName,
                snapshotName: name,
                volumePath: mountPoint
            )
        }
        DebugLogger.log("listBackupsViaAPFS: \(result.count) TM snapshots on \(mountPoint)")
        return result.sorted { $0.date > $1.date }
    }

    // MARK: - Volume Info

    func getVolumeInfo(mountPoint: String) async -> TMUtilTypes.VolumeInfo? {
        guard let output = try? await run("/usr/sbin/diskutil", args: ["info", "-plist", mountPoint]),
              let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            DebugLogger.log("getVolumeInfo: diskutil info failed for \(mountPoint)")
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

        let info = TMUtilTypes.VolumeInfo(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            freeBytes: freeBytes,
            filesystem: fileSystem,
            deviceNode: devNode,
            solidState: ssd,
            volumeKind: kind
        )
        DebugLogger.log(
            "getVolumeInfo: total=\(totalBytes) used=\(usedBytes) free=\(freeBytes) kind=\(kind) ssd=\(ssd)"
        )
        return info
    }

    // MARK: - Delete

    func deleteBackup(_ backup: TimeMachineBackup) async throws {
        guard let mountPoint = backup.volumePath,
              let snapshotName = backup.snapshotName else {
            DebugLogger.log("deleteBackup: missing volumePath or snapshotName")
            throw TMUtilTypes.TMError.backupParsingFailed
        }

        DebugLogger.log("deleteBackup: snapshot=\(snapshotName) mount=\(mountPoint) path=\(backup.path)")

        // Strategy 1: tmutil deletebackups with direct path (preferred on macOS 26+)
        if !backup.path.isEmpty {
            do {
                let escapedPath = backup.path.replacingOccurrences(of: "\"", with: "\\\"")
                try await runPrivileged("/usr/bin/tmutil deletebackups \"\(escapedPath)\"")
                DebugLogger.log("deleteBackup: ✅ tmutil deleted \(snapshotName)")
                return
            } catch {
                DebugLogger.log("deleteBackup: tmutil failed, trying diskutil — \(error.localizedDescription)")
            }
        } else {
            DebugLogger.log("deleteBackup: no tmutil path available, using diskutil")
        }

        // Strategy 2: diskutil apfs deleteSnapshot with force unmount
        let datePart = snapshotName
            .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
            .replacingOccurrences(of: ".backup", with: "")
        let escapedName = snapshotName.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMount = mountPoint.replacingOccurrences(of: "\"", with: "\\\"")

        // Step A: Find UUID in Swift by enumerating /Volumes/.timemachine/
        if let uuid = findSnapshotUUID(datePart: datePart) {
            let snapshotPath = "/Volumes/.timemachine/\(uuid)/\(datePart).backup"
            let escapedSnapPath = snapshotPath.replacingOccurrences(of: "\"", with: "\\\"")
            DebugLogger.log("deleteBackup: found UUID=\(uuid), force unmounting \(snapshotPath)")

            // Step B: Force unmount the snapshot path
            let unmountResult = try? await runPrivileged(
                "/usr/sbin/diskutil unmount force \"\(escapedSnapPath)\""
            )
            DebugLogger.log("deleteBackup: unmount result=\(unmountResult ?? "failed or already unmounted")")
        } else {
            DebugLogger.log("deleteBackup: UUID not found under /Volumes/.timemachine/")
        }

        // Step C: Delete the snapshot
        do {
            try await runPrivileged(
                "/usr/sbin/diskutil apfs deleteSnapshot \"\(escapedMount)\" -name \"\(escapedName)\""
            )
            DebugLogger.log("deleteBackup: ✅ diskutil deleted \(snapshotName)")
        } catch let error as TMUtilTypes.TMError {
            if case .processFailed(let raw) = error {
                let errorCode = TMUtilTypes.parseErrorCode(raw)
                let codePrefix = errorCode.map { "Error \($0): " } ?? ""
                DebugLogger.log("deleteBackup: ❌ \(snapshotName) → Error \(codePrefix)\(raw)")
                throw TMUtilTypes.TMError.deleteFailed("\(codePrefix)\(raw)")
            }
            throw error
        }
    }

    /// Iterates /Volumes/.timemachine/*/ to find the UUID containing the given datePart
    private func findSnapshotUUID(datePart: String) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes/.timemachine") else {
            return nil
        }
        for entry in entries {
            let candidate = "/Volumes/.timemachine/\(entry)/\(datePart).backup"
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                return entry
            }
        }
        return nil
    }
}
