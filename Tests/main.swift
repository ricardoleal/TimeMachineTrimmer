import Foundation

print("TimeMachineTrimmer Tests")
print("================================================")

// ============================================================
// Unit Tests
// ============================================================

print("\n## ResumptionFlag")
testResumptionFlag_firstCallReturnsTrue()
testResumptionFlag_secondCallReturnsFalse()
testResumptionFlag_threadSafety()

print("\n## Date Part Extraction")
testDatePartExtraction_fullName()
testDatePartExtraction_nonTMName()
testDatePartExtraction_empty()

print("\n## Backup Dict Validation")
testBackupDictValidation_valid()
testBackupDictValidation_missingSnapshot()
testBackupDictValidation_missingVolume()
testBackupDictValidation_emptyDict()

print("\n## HelperClient Backup Dict")
testBackupDict_hasAllKeys()
testBackupDict_valuesPreserved()
testBackupDict_emptyValues()

print("\n## XPC Reply Format")
testXPCReply_successIsEmptyString()
testXPCReply_errorIsNonEmptyString()
testXPCReply_mixedResults()

// ============================================================
// Integration Tests
// ============================================================

runIntegrationTests()

// ============================================================
// Summary
// ============================================================

printSummary()
