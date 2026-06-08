import Foundation

enum DebugLogger {
    private static let logFile: URL = {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/TimeMachineTrimmer")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        return configDir.appendingPathComponent("debug.log")
    }()

    private static let queue = DispatchQueue(label: "com.ricardoleal.debug-logger", qos: .utility)
    private static var headerWritten = false

    static var logPath: String { logFile.path }

    static func log(_ message: String) {
        queue.async {
            writeHeaderIfNeeded()

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let entry = "[\(timestamp)] \(message)\n"
            guard let data = entry.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logFile)
            }

            if let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
               let size = attrs[.size] as? Int64,
               size > 5_000_000,
               let fileData = try? Data(contentsOf: logFile) {
                try? fileData.dropFirst(fileData.count / 2).write(to: logFile)
            }
        }
    }

    private static func writeHeaderIfNeeded() {
        guard !headerWritten else { return }
        headerWritten = true

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let build = ProcessInfo.processInfo.operatingSystemVersionString
        let header = """
        ─────────────────────────────────────────────
        TimeMachineTrimmer Debug Log
        macOS: \(osVersion)
        Started: \(ISO8601DateFormatter().string(from: Date()))
        ─────────────────────────────────────────────

        """
        guard let data = header.data(using: .utf8) else { return }
        try? data.write(to: logFile)
    }

    static func clear() {
        queue.async {
            headerWritten = false
            try? "".data(using: .utf8)?.write(to: logFile)
        }
    }
}
