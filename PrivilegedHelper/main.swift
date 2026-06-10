import Foundation

// MARK: - Helper Daemon

let helperVersion = "1.0"

class HelperDaemon: NSObject, NSXPCListenerDelegate, HelperProtocol {

    private let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(machServiceName: "com.ricardoleal.TimeMachineTrimmerHelper")
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
        RunLoop.current.run()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    // MARK: - HelperProtocol

    func ping(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func version(withReply reply: @escaping (String) -> Void) {
        reply(helperVersion)
    }

    func deleteBackups(_ backups: [[String: String]], withReply reply: @escaping ([String: String]) -> Void) {
        var results: [String: String] = [:]
        for backup in backups {
            let id = backup["id"] ?? "unknown"
            results[id] = deleteSingleBackup(backup) ?? ""
        }
        reply(results)
    }

    // MARK: - Deletion Logic

    /// Returns nil on success, or an error message string on failure.
    private func deleteSingleBackup(_ backup: [String: String]) -> String? {
        guard let volumePath = backup["volumePath"], let snapshotName = backup["snapshotName"],
              !volumePath.isEmpty, !snapshotName.isEmpty else {
            return "Missing volumePath or snapshotName"
        }

        let datePart = snapshotName
            .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
            .replacingOccurrences(of: ".backup", with: "")

        // Step A: Find UUID and force unmount
        if let uuid = findSnapshotUUID(datePart: datePart) {
            let snapshotPath = "/Volumes/.timemachine/\(uuid)/\(datePart).backup"
            _ = run("/usr/sbin/diskutil", args: ["unmount", "force", snapshotPath])
        }

        // Step B: Delete the snapshot
        let deleteError = run("/usr/sbin/diskutil", args: [
            "apfs", "deleteSnapshot", volumePath, "-name", snapshotName
        ])
        if let deleteError {
            return deleteError
        }

        return nil
    }

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

    // MARK: - Process Execution

    /// Runs a command and returns nil on success, or an error message on failure.
    @discardableResult
    private func run(_ executable: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        process.launch()
        process.waitUntilExit()

        guard process.terminationStatus != 0 else { return nil }

        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let error = String(data: err, encoding: .utf8) ?? ""
        let output = String(data: out, encoding: .utf8) ?? ""
        let msg = error.isEmpty ? output : error
        return msg.isEmpty ? "Command failed with exit code \(process.terminationStatus)" : msg
    }
}

// MARK: - Main

let daemon = HelperDaemon()
daemon.start()
