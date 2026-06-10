import Foundation

// MARK: - Test Assertions

private var passed = 0
private var failed = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") {
    if actual == expected {
        pass(message.isEmpty ? "\(actual) == \(expected)" : message)
    } else {
        fail(message.isEmpty ? "\(actual) != \(expected)" : message,
             details: "expected: \(expected)\n    actual:   \(actual)")
    }
}

func assertTrue(_ actual: Bool, _ message: String = "") {
    assertEqual(actual, true, message)
}

func assertFalse(_ actual: Bool, _ message: String = "") {
    assertEqual(actual, false, message)
}

func assertNil<T>(_ actual: T?, _ message: String = "") {
    if actual == nil {
        pass(message.isEmpty ? "nil" : message)
    } else {
        fail(message.isEmpty ? "expected nil" : message)
    }
}

func assertNotNil<T>(_ actual: T?, _ message: String = "") {
    if actual != nil {
        pass(message.isEmpty ? "not nil" : message)
    } else {
        fail(message.isEmpty ? "expected non-nil" : message)
    }
}

func assertContains(_ haystack: String, _ needle: String, _ message: String = "") {
    if haystack.contains(needle) {
        pass(message.isEmpty ? "'\(haystack)' contains '\(needle)'" : message)
    } else {
        fail(message.isEmpty ? "'\(haystack)' does not contain '\(needle)'" : message)
    }
}

func pass(_ message: String) {
    passed += 1
    print("  ✓ \(message)")
}

func fail(_ message: String, details: String = "") {
    failed += 1
    print("  ✗ \(message)")
    if !details.isEmpty { print("    \(details)") }
}

func printSummary() {
    print("\n──────────────────────────────")
    print("\(passed) passed, \(failed) failed")
    print("──────────────────────────────")
    if failed > 0 { exit(1) }
}

// MARK: - Shell Helper

@discardableResult
func shell(_ command: String, arguments: [String] = []) -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    process.launch()
    process.waitUntilExit()

    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

    return (
        process.terminationStatus,
        String(data: outData, encoding: .utf8) ?? "",
        String(data: errData, encoding: .utf8) ?? ""
    )
}
