import Foundation

let serviceName = "com.ricardoleal.TimeMachineTrimmerHelper"

func printUsage() {
    print("""
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
    return connection.remoteObjectProxy as! HelperProtocol
}

func cmdPing() {
    print("Pinging helper at \(serviceName)...")
    let proxy = connectToHelper()
    proxy.ping { alive in
        print(alive ? "✓ Helper is alive" : "✗ Helper not responding")
        exit(alive ? 0 : 1)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(5))
}

func cmdVersion() {
    print("Getting helper version...")
    let proxy = connectToHelper()
    proxy.version { version in
        print("Helper version: \(version)")
        exit(0)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(5))
}

func cmdStatus() {
    print("Checking helper status...")

    let binaryPath = "/usr/local/bin/TimeMachineTrimmer-helper"
    let plistPath = "/Library/LaunchDaemons/com.ricardoleal.TimeMachineTrimmer.helper.plist"

    let binaryExists = FileManager.default.fileExists(atPath: binaryPath)
    let plistExists = FileManager.default.fileExists(atPath: plistPath)

    print("  Binary: \(binaryExists ? "✓ \(binaryPath)" : "✗ Not found")")
    print("  Plist:  \(plistExists ? "✓ \(plistPath)" : "✗ Not found")")

    if binaryExists && plistExists {
        print("  Testing connection...")
        let proxy = connectToHelper()
        proxy.ping { alive in
            print("  Connection: \(alive ? "✓ Connected" : "✗ Not responding")")
            exit(alive ? 0 : 1)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(5))
    } else {
        print("\nHelper not installed. Run: tmt-helper-cli install")
        exit(1)
    }
}

func cmdInstall() {
    print("Installing helper...")
    print("This requires administrator privileges.")

    let cwd = FileManager.default.currentDirectoryPath
    let helperSrc = "\(cwd)/build/TimeMachineTrimmer.app/Contents/Library/LaunchServices/TimeMachineTrimmer-helper"
    let plistSrc = "\(cwd)/build/TimeMachineTrimmer.app/Contents/Library/LaunchServices/com.ricardoleal.TimeMachineTrimmer.helper.plist"

    guard FileManager.default.fileExists(atPath: helperSrc) else {
        print("Error: Could not find helper binary at \(helperSrc)")
        print("Run from project root after building: .scripts/build.sh")
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
    task.arguments = ["-e", "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"]

    task.launch()
    task.waitUntilExit()

    if task.terminationStatus == 0 {
        print("✓ Helper installed successfully")
    } else {
        print("✗ Installation failed")
        exit(1)
    }
}

func cmdUninstall() {
    print("Uninstalling helper...")
    print("This requires administrator privileges.")

    let script = """
    launchctl bootout system/com.ricardoleal.TimeMachineTrimmer.helper 2>/dev/null; \
    rm -f /usr/local/bin/TimeMachineTrimmer-helper; \
    rm -f /Library/LaunchDaemons/com.ricardoleal.TimeMachineTrimmer.helper.plist
    """

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    task.arguments = ["-e", "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"]

    task.launch()
    task.waitUntilExit()

    if task.terminationStatus == 0 {
        print("✓ Helper uninstalled successfully")
    } else {
        print("✗ Uninstall failed")
        exit(1)
    }
}

func cmdDelete(args: [String]) {
    var snapshotName = ""
    var volumePath = ""
    var path = ""

    var i = 0
    while i < args.count {
        switch args[i] {
        case "--snapshot":
            i += 1
            snapshotName = args[i]
        case "--volume":
            i += 1
            volumePath = args[i]
        case "--path":
            i += 1
            path = args[i]
        default:
            break
        }
        i += 1
    }

    guard !snapshotName.isEmpty, !volumePath.isEmpty else {
        print("Error: --snapshot and --volume are required")
        printUsage()
        exit(1)
    }

    print("Deleting backup...")
    print("  Snapshot: \(snapshotName)")
    print("  Volume:   \(volumePath)")
    if !path.isEmpty {
        print("  Path:     \(path)")
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
                print("\n✓ Deleted: \(id)")
            } else {
                print("\n✗ Failed: \(id)")
                print("  Error: \(error)")
            }
        }
        exit(results.values.allSatisfy { $0.isEmpty } ? 0 : 1)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(30))
}

// MARK: - Main

@main
struct CLI {
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
            print("Unknown command: \(command)")
            printUsage()
            exit(1)
        }
    }
}
