import Foundation

/// Simple wrapper to safely share a flag across contexts
private final class ResumptionFlag {
    private var resumed = false
    private let lock = NSLock()

    /// Returns true if this is the first call, false if already resumed
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

actor HelperClient {

    private var connection: NSXPCConnection?

    private let machServiceName = "com.ricardoleal.TimeMachineTrimmerHelper"
    private let helperBinary = "/usr/local/bin/TimeMachineTrimmer-helper"
    private let helperPlist = "/Library/LaunchDaemons/com.ricardoleal.TimeMachineTrimmer.helper.plist"

    // MARK: - Installation Check

    nonisolated var isInstalled: Bool {
        FileManager.default.fileExists(atPath: helperBinary)
            && FileManager.default.fileExists(atPath: helperPlist)
    }

    // MARK: - Install

    func ensureInstalled() throws {
        guard !isInstalled else { return }

        let bundlePath = Bundle.main.bundlePath
        let srcBinary = "\(bundlePath)/Contents/Library/LaunchServices/TimeMachineTrimmer-helper"
        let srcPlist = "\(bundlePath)/Contents/Library/LaunchServices/com.ricardoleal.TimeMachineTrimmer.helper.plist"

        guard FileManager.default.fileExists(atPath: srcBinary) else {
            throw TMUtilTypes.TMError.processFailed("Helper binary not found in app bundle")
        }

        let script = """
        cp "\(srcBinary)" "\(helperBinary)" && \
        chmod 755 "\(helperBinary)" && \
        cp "\(srcPlist)" "\(helperPlist)" && \
        launchctl bootstrap system "\(helperPlist)"
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e",
            "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        ]

        let errPipe = Pipe()
        task.standardError = errPipe

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            if errMsg.localizedCaseInsensitiveContains("cancelled")
                || errMsg.localizedCaseInsensitiveContains("(-128)") {
                throw TMUtilTypes.TMError.processFailed("Installation cancelled by user")
            }
            throw TMUtilTypes.TMError.processFailed("Helper installation failed: \(errMsg)")
        }
    }

    // MARK: - Uninstall

    nonisolated func uninstall() throws {
        let script = """
        launchctl bootout system "\(helperPlist)" 2>/dev/null || true
        rm -f "\(helperBinary)" "\(helperPlist)"
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e",
            "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        ]

        let errPipe = Pipe()
        task.standardError = errPipe

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            if errMsg.localizedCaseInsensitiveContains("cancelled")
                || errMsg.localizedCaseInsensitiveContains("(-128)") {
                throw TMUtilTypes.TMError.processFailed("Uninstallation cancelled by user")
            }
            throw TMUtilTypes.TMError.processFailed("Helper uninstallation failed: \(errMsg)")
        }
    }

    // MARK: - Connection

    private func connect() throws -> HelperProtocol {
        if let existing = connection {
            return existing.remoteObjectProxy as! HelperProtocol // swiftlint:disable:this force_cast
        }

        let newConnection = NSXPCConnection(machServiceName: machServiceName)
        newConnection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.interruptionHandler = { [weak self] in
            Task { [weak self] in
                await self?.handleInterruption()
            }
        }
        newConnection.invalidationHandler = { [weak self] in
            Task { [weak self] in
                await self?.handleInvalidation()
            }
        }
        newConnection.resume()
        connection = newConnection

        guard let proxy = newConnection.remoteObjectProxy as? HelperProtocol else {
            throw TMUtilTypes.TMError.processFailed("Could not create XPC proxy")
        }
        return proxy
    }

    private func handleInterruption() {
        connection = nil
    }

    private func handleInvalidation() {
        connection = nil
    }

    // MARK: - Protocol Methods

    func ping() async throws -> Bool {
        let proxy = try connect()
        return try await withCheckedThrowingContinuation { continuation in
            let flag = ResumptionFlag()

            proxy.ping { alive in
                if flag.tryResume() {
                    continuation.resume(returning: alive)
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(5))
                if flag.tryResume() {
                    continuation.resume(throwing: TMUtilTypes.TMError.processFailed("XPC call timed out"))
                }
            }
        }
    }

    func version() async throws -> String {
        let proxy = try connect()
        return try await withCheckedThrowingContinuation { continuation in
            let flag = ResumptionFlag()

            proxy.version { version in
                if flag.tryResume() {
                    continuation.resume(returning: version)
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(5))
                if flag.tryResume() {
                    continuation.resume(throwing: TMUtilTypes.TMError.processFailed("XPC call timed out"))
                }
            }
        }
    }

    func deleteBackups(_ backups: [TimeMachineBackup]) async throws -> [String: String] {
        let proxy = try connect()

        let helperBackups: [[String: String]] = backups.compactMap { backup in
            guard let volumePath = backup.volumePath, let snapshotName = backup.snapshotName else {
                return nil
            }
            return [
                "id": backup.id,
                "path": backup.path,
                "snapshotName": snapshotName,
                "volumePath": volumePath
            ]
        }

        return try await withCheckedThrowingContinuation { continuation in
            let flag = ResumptionFlag()

            proxy.deleteBackups(helperBackups) { results in
                if flag.tryResume() {
                    continuation.resume(returning: results)
                }
            }

            Task {
                try? await Task.sleep(for: .seconds(30))
                if flag.tryResume() {
                    continuation.resume(
                        throwing: TMUtilTypes.TMError.processFailed("XPC call timed out")
                    )
                }
            }
        }
    }
}
