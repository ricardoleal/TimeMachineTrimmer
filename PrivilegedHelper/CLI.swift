import Foundation

let serviceName = "com.ricardoleal.TimeMachineTrimmerHelper"

// swiftlint:disable:next no_print_statements
func log(_ message: String) { print(message) }

func printUsage() {
    log("""
    TimeMachineTrimmer Helper CLI

    Usage: tmt-helper-cli <command>

    Commands:
      ping              Test connection to helper
      version           Get helper version
      status            Check if helper is installed and running
      delete <args>     Test deleting a backup (requires admin)
      install           Install helper to system
      uninstall         Remove helper from system

    Delete arguments:
      --snapshot <name>   Snapshot name (e.g. com.apple.TimeMachine.2025-06-09-143022.backup)
      --volume <path>     Volume path (e.g. /Volumes/BackupDisk)
      --path <path>       Backup path (optional, for tmutil strategy)

    Examples:
      tmt-helper-cli ping
      tmt-helper-cli version
      tmt-helper-cli delete --snapshot "com.apple.TimeMachine.2025-06-09-143022.backup" --volume "/Volumes/BackupDisk"
    """)
}

func connectToHelper() -> HelperProtocol {
    let connection = NSXPCConnection(machServiceName: serviceName)
    connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
    connection.resume()
    guard let proxy = connection.remoteObjectProxy as? HelperProtocol else {
        log("Error: Could not connect to helper")
        exit(1)
    }
    return proxy
}

func cmdPing() {
    log("Pinging helper at \(serviceName)...")
    let proxy = connectToHelper()
    proxy.ping { alive in
        log(alive ? "✓ Helper is alive" : "✗ Helper not responding")
        exit(alive ? 0 : 1)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(5))
}

func cmdVersion() {
    log("Getting helper version...")
    let proxy = connectToHelper()
    proxy.version { version in
        log("Helper version: \(version)")
        exit(0)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(5))
}

func cmdStatus() {
    log("Checking helper status...")

    let binaryPath = "/usr/local/bin/TimeMachineTrimmer-helper"
    let plistPath = "/Library/LaunchDaemons/com.ricardoleal.TimeMachineTrimmer.helper.plist"

    let binaryExists = FileManager.default.fileExists(atPath: binaryPath)
    let plistExists = FileManager.default.fileExists(atPath: plistPath)

    log("  Binary: \(binaryExists ? "✓ \(binaryPath)" : "✗ Not found")")
    log("  Plist:  \(plistExists ? "✓ \(plistPath)" : "✗ Not found")")

    if binaryExists && plistExists {
        log("  Testing connection...")
        let proxy = connectToHelper()
        proxy.ping { alive in
            log("  Connection: \(alive ? "✓ Connected" : "✗ Not responding")")
            exit(alive ? 0 : 1)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(5))
    } else {
        log("\nHelper not installed. Run: tmt-helper-cli install")
        exit(1)
    }
}

func cmdInstall() {
    log("Installing helper...")
    log("This requires administrator privileges.")

    let cwd = FileManager.default.currentDirectoryPath
    let buildPath = "\(cwd)/build/TimeMachineTrimmer.app/Contents/Library/LaunchServices"
    let helperSrc = "\(buildPath)/TimeMachineTrimmer-helper"
    let plistSrc = "\(buildPath)/com.ricardoleal.TimeMachineTrimmer.helper.plist"

    guard FileManager.default.fileExists(atPath: helperSrc) else {
        log("Error: Could not find helper binary at \(helperSrc)")
        log("Run from project root after building: .scripts/build.sh")
        exit(1)
    }

    let helperDst = "/usr/local/bin/TimeMachineTrimmer-helper"
    let plistDst = "/Library/LaunchDaemons/com.ricardoleal.TimeMachineTrimmer.helper.plist"

    let script = """
    cp "\(helperSrc)" "\(helperDst)" && \
    chmod 755 "\(helperDst)" && \
    cp "\(plistSrc)" "\(plistDst)" && \
    launchctl bootstrap system "\(plistDst)"
    """

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = [
        "-e",
        "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
    ]

    task.launch()
    task.waitUntilExit()

    if task.terminationStatus == 0 {
        log("✓ Helper installed successfully")
    } else {
        log("✗ Installation failed")
        exit(1)
    }
}

func cmdUninstall() {
    log("Uninstalling helper...")
    log("This requires administrator privileges.")

    let script = """
    launchctl bootout system/com.ricardoleal.TimeMachineTrimmer.helper 2>/dev/null; \
    rm -f /usr/local/bin/TimeMachineTrimmer-helper; \
    rm -f /Library/LaunchDaemons/com.ricardoleal.TimeMachineTrimmer.helper.plist
    """

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = [
        "-e",
        "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
    ]

    task.launch()
    task.waitUntilExit()

    if task.terminationStatus == 0 {
        log("✓ Helper uninstalled successfully")
    } else {
        log("✗ Uninstall failed")
        exit(1)
    }
}

func cmdDelete(args: [String]) {
    var snapshotName = ""
    var volumePath = ""
    var path = ""

    var index = 0
    while index < args.count {
        switch args[index] {
        case "--snapshot":
            index += 1
            snapshotName = args[index]
        case "--volume":
            index += 1
            volumePath = args[index]
        case "--path":
            index += 1
            path = args[index]
        default:
            break
        }
        index += 1
    }

    guard !snapshotName.isEmpty, !volumePath.isEmpty else {
        log("Error: --snapshot and --volume are required")
        printUsage()
        exit(1)
    }

    log("Deleting backup...")
    log("  Snapshot: \(snapshotName)")
    log("  Volume:   \(volumePath)")
    if !path.isEmpty {
        log("  Path:     \(path)")
    }

    let backup = HelperBackup(
        id: snapshotName,
        path: path,
        snapshotName: snapshotName,
        volumePath: volumePath
    )

    let proxy = connectToHelper()
    proxy.deleteBackups([backup]) { results in
        for (id, error) in results {
            if error.isEmpty {
                log("\n✓ Deleted: \(id)")
            } else {
                log("\n✗ Failed: \(id)")
                log("  Error: \(error)")
            }
        }
        exit(results.values.allSatisfy { $0.isEmpty } ? 0 : 1)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(30))
}

// MARK: - Main

enum CLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        guard let command = args.first else {
            printUsage()
            exit(0)
        }

        switch command {
        case "ping":
            cmdPing()
        case "version":
            cmdVersion()
        case "status":
            cmdStatus()
        case "install":
            cmdInstall()
        case "uninstall":
            cmdUninstall()
        case "delete":
            cmdDelete(args: Array(args.dropFirst()))
        case "--help", "-h", "help":
            printUsage()
        default:
            log("Unknown command: \(command)")
            printUsage()
            exit(1)
        }
    }
}
