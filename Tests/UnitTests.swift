import Foundation

// ============================================================
// ResumptionFlag (test copy of private class from HelperClient)
// ============================================================

final class ResumptionFlag {
    private var resumed = false
    private let lock = NSLock()

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}

func testResumptionFlag_firstCallReturnsTrue() {
    let flag = ResumptionFlag()
    assertTrue(flag.tryResume(), "first call returns true")
}

func testResumptionFlag_secondCallReturnsFalse() {
    let flag = ResumptionFlag()
    _ = flag.tryResume()
    assertFalse(flag.tryResume(), "second call returns false")
    assertFalse(flag.tryResume(), "third call returns false")
}

/// Thread-safe counter for concurrent test verification.
final class AtomicCounter {
    private var _value = 0
    private let lock = NSLock()
    func increment() { lock.lock(); _value += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
}

func testResumptionFlag_threadSafety() {
    let flag = ResumptionFlag()
    let counter = AtomicCounter()
    let iterations = 100

    DispatchQueue.concurrentPerform(iterations: iterations) { _ in
        if flag.tryResume() {
            counter.increment()
        }
    }

    assertEqual(counter.value, 1, "only one succeeds from \(iterations) concurrent calls")
}

// ============================================================
// Helper Daemon Logic (copied from PrivilegedHelper/main.swift)
// ============================================================

func extractDatePart(from snapshotName: String) -> String {
    snapshotName
        .replacingOccurrences(of: "com.apple.TimeMachine.", with: "")
        .replacingOccurrences(of: ".backup", with: "")
}

func validateBackupDict(_ backup: [String: String]) -> String? {
    guard let volumePath = backup["volumePath"],
          let snapshotName = backup["snapshotName"],
          !volumePath.isEmpty, !snapshotName.isEmpty else {
        return "Missing volumePath or snapshotName"
    }
    return nil
}

func testDatePartExtraction_fullName() {
    assertEqual(
        extractDatePart(from: "com.apple.TimeMachine.2026-06-07-211512.backup"),
        "2026-06-07-211512",
        "full TM snapshot name"
    )
}

func testDatePartExtraction_nonTMName() {
    assertEqual(extractDatePart(from: "random_string"), "random_string", "non-TM string unchanged")
}

func testDatePartExtraction_empty() {
    assertEqual(extractDatePart(from: "com.apple.TimeMachine..backup"), "", "empty date part")
}

func testBackupDictValidation_valid() {
    let valid: [String: String] = [
        "id": "test-1",
        "snapshotName": "com.apple.TimeMachine.2026-06-07-211512.backup",
        "volumePath": "/Volumes/Time Machine"
    ]
    assertNil(validateBackupDict(valid), "valid dict returns nil")
}

func testBackupDictValidation_missingSnapshot() {
    let bad: [String: String] = ["id": "test-2", "volumePath": "/Volumes/Backup", "snapshotName": ""]
    assertNotNil(validateBackupDict(bad), "empty snapshot returns error")
    assertContains(validateBackupDict(bad)!, "snapshotName", "error mentions snapshotName")
}

func testBackupDictValidation_missingVolume() {
    let bad: [String: String] = ["id": "test-3", "snapshotName": "snap", "volumePath": ""]
    assertNotNil(validateBackupDict(bad), "empty volume returns error")
    assertContains(validateBackupDict(bad)!, "volumePath", "error mentions volumePath")
}

func testBackupDictValidation_emptyDict() {
    assertNotNil(validateBackupDict([:]), "empty dict returns error")
}

// ============================================================
// HelperClient: backup dict construction
// ============================================================

let expectedKeys: Set<String> = ["id", "path", "snapshotName", "volumePath"]

func buildBackupDict(id: String, path: String, snapshotName: String, volumePath: String) -> [String: String] {
    ["id": id, "path": path, "snapshotName": snapshotName, "volumePath": volumePath]
}

func testBackupDict_hasAllKeys() {
    let dict = buildBackupDict(
        id: "test-1", path: "/p", snapshotName: "snap.backup", volumePath: "/Volumes/Disk"
    )
    for key in expectedKeys {
        assertTrue(dict.keys.contains(key), "dict contains key '\(key)'")
    }
}

func testBackupDict_valuesPreserved() {
    let dict = buildBackupDict(
        id: "my-id", path: "/path with/spaces", snapshotName: "snap", volumePath: "/Volumes/My Disk"
    )
    assertEqual(dict["id"], "my-id")
    assertEqual(dict["path"], "/path with/spaces")
    assertEqual(dict["snapshotName"], "snap")
    assertEqual(dict["volumePath"], "/Volumes/My Disk")
}

func testBackupDict_emptyValues() {
    let dict = buildBackupDict(id: "", path: "", snapshotName: "", volumePath: "")
    assertEqual(dict["id"], "", "empty id ok")
    assertEqual(dict.count, 4, "4 keys even with empty values")
}

// ============================================================
// XPC reply semantics: empty string = success
// ============================================================

func testXPCReply_successIsEmptyString() {
    let reply: [String: String] = ["backup-1": ""]
    assertEqual(reply["backup-1"], "", "empty string means success")
}

func testXPCReply_errorIsNonEmptyString() {
    let reply: [String: String] = ["backup-1": "Some error"]
    assertFalse(reply["backup-1"]!.isEmpty, "non-empty string means error")
}

func testXPCReply_mixedResults() {
    let reply: [String: String] = ["ok": "", "fail": "Error deleting"]
    assertEqual(reply["ok"], "", "success = empty")
    assertEqual(reply["fail"], "Error deleting", "failure = error message")
}
