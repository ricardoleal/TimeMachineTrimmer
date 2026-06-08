import Foundation

enum TMUtilTypes {

    // MARK: - Errors

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

    // MARK: - Models

    struct BackupStatus {
        let running: Bool
        let firstBackup: Bool
        let phase: String
        let percent: Double
        let timeRemaining: TimeInterval
        let files: Int
        let totalFiles: Int
    }

    struct VolumeInfo {
        let totalBytes: Int64
        let usedBytes: Int64
        let freeBytes: Int64
        let filesystem: String
        let deviceNode: String
        let solidState: Bool
        let volumeKind: String
    }

    // MARK: - Parsing

    static func parseBackupStatus(_ output: String) -> BackupStatus {
        let running = output.contains("Running = 1")
        let firstBackup = output.contains("FirstBackup = 1")
        let phase = Self.extractTMValue(from: output, key: "BackupPhase") ?? ""
        let percent = Double(Self.extractTMValue(from: output, key: "Percent") ?? "") ?? 0
        let timeRemaining = TimeInterval(Self.extractTMValue(from: output, key: "TimeRemaining") ?? "") ?? 0
        let files = Int(Self.extractTMValue(from: output, key: "files") ?? "") ?? 0
        let totalFiles = Int(Self.extractTMValue(from: output, key: "totalFiles") ?? "") ?? 0
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

    /// Extracts numeric error codes (e.g. -69528) from osascript/command output
    static func parseErrorCode(_ output: String) -> String? {
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

    static func parseBackupDate(from name: String) -> Date? {
        let patterns = [
            #"^(\d{4})-(\d{2})-(\d{2})-(\d{6})(\.backup)?$"#,
            #"\.(\d{4})-(\d{2})-(\d{2})-(\d{6})"#
        ]
        for pattern in patterns {
            if let date = Self.parseDateWithPattern(pattern, in: name) { return date }
        }
        return nil
    }

    private static func parseDateWithPattern(_ pattern: String, in name: String) -> Date? {
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
