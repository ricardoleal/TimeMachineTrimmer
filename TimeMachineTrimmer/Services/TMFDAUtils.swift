import Foundation

enum TMFDAUtils {

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
            let granted = !errorOutput.contains("Full Disk Access")
            DebugLogger.log("checkFDA: tmutil listbackups → \(granted ? "granted" : "denied")")
            if !granted { DebugLogger.log("checkFDA: stderr=\(errorOutput)") }
            return granted
        } catch {
            DebugLogger.log("checkFDA: exception → false (\(error.localizedDescription))")
            return false
        }
    }

    static func triggerFDAuthorizationPrompt() {
        DebugLogger.log("triggerFDAuthorizationPrompt: touching /.vol and /Volumes/.TMExcludeStore")
        let paths = ["/.vol", "/Volumes/.TMExcludeStore"]
        for path in paths {
            _ = FileManager.default.isReadableFile(atPath: path)
            _ = FileManager.default.contents(atPath: path)
        }
    }

    static func backupStatus() -> TMUtilTypes.BackupStatus {
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
            let status = TMUtilTypes.parseBackupStatus(output)
            DebugLogger.log("backupStatus: running=\(status.running) phase=\(status.phase) percent=\(status.percent)")
            return status
        } catch {
            DebugLogger.log("backupStatus: exception → idle (\(error.localizedDescription))")
            return TMUtilTypes.BackupStatus(
                running: false, firstBackup: false,
                phase: "", percent: 0, timeRemaining: 0,
                files: 0, totalFiles: 0
            )
        }
    }
}
