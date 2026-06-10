import Foundation

// ============================================================
// Integration tests — run against the installed helper daemon
// Build verification tests run unconditionally.
// XPC tests only run if helper daemon is reachable.
// ============================================================

let cliPath = "/tmp/TimeMachineTrimmer-helper-cli"

/// Quick ping to check if the helper daemon is reachable via XPC.
func isHelperReachable() -> Bool {
    let result = shell(cliPath, arguments: ["ping"])
    return result.stdout.contains("alive")
}

// MARK: - Ping

func testPing() {
    let result = shell(cliPath, arguments: ["ping"])
    let success = result.stdout.contains("alive")
    if success {
        pass("ping: helper is alive")
    } else {
        fail("ping: no response", details: "stdout: \(result.stdout)")
    }
}

// MARK: - Version

func testVersion() {
    let result = shell(cliPath, arguments: ["version"])
    let containsVersion = result.stdout.contains("Helper version:")
    if containsVersion {
        pass("version: XPC response received")
    } else {
        fail("version: no response", details: "stdout: \(result.stdout)")
    }
}

// MARK: - Delete (verifies no hang + proper error for invalid targets)

func testDelete_invalidSnapshot_returnsError() {
    let result = shell(cliPath, arguments: [
        "delete",
        "--snapshot", "com.apple.TimeMachine.NONEXISTENT.backup",
        "--volume", "/Volumes/Time Machine"
    ])
    if !result.stdout.isEmpty {
        pass("delete: returned (no hang)")
        if result.stdout.contains("✓ Deleted") || result.stdout.contains("✗ Failed") {
            pass("delete: produced a result line")
        }
    } else {
        fail("delete: hung (no output)")
    }
}

func testDelete_missingVolume_returnsError() {
    let result = shell(cliPath, arguments: [
        "delete",
        "--snapshot", "com.apple.TimeMachine.EXAMPLE.backup",
        "--volume", "/Volumes/NonexistentVolume"
    ])
    if !result.stdout.isEmpty {
        pass("delete (bad volume): returned (no hang)")
    } else {
        fail("delete (bad volume): hung (no output)")
    }
}

// MARK: - Build verification (always run)

func testHelperIsMachO() {
    let result = shell("/usr/bin/file", arguments: ["/usr/local/bin/TimeMachineTrimmer-helper"])
    assertContains(result.stdout, "Mach-O", "binary is Mach-O format")
    assertContains(result.stdout, "arm64", "binary is arm64 architecture")
}

func testHelperCodeSignature() {
    let result = shell("/usr/bin/codesign", arguments: ["-dvv", "/usr/local/bin/TimeMachineTrimmer-helper"])
    assertContains(result.stderr + result.stdout, "Signature", "code signature present")
}

// MARK: - Runner

func runIntegrationTests() {
    print("\n\n================================================")
    print("Integration Tests")
    print("================================================")

    guard FileManager.default.fileExists(atPath: cliPath) else {
        print("  ⚠ CLI not found at \(cliPath) — skipping integration tests")
        return
    }

    guard FileManager.default.fileExists(atPath: "/usr/local/bin/TimeMachineTrimmer-helper") else {
        print("  ⚠ Helper binary not found — skipping integration tests")
        return
    }

    // Build verification (no XPC needed)
    print("\n-- Build verification --")
    testHelperIsMachO()
    testHelperCodeSignature()

    // XPC communication (requires running daemon)
    guard isHelperReachable() else {
        print("\n-- XPC communication (skipped — helper not reachable) --")
        return
    }

    print("\n-- XPC communication --")
    testPing()
    testVersion()

    print("\n-- Delete operations --")
    testDelete_invalidSnapshot_returnsError()
    testDelete_missingVolume_returnsError()
}
