# AI Agent Guidelines for TimeMachineTrimmer

This file provides instructions for AI agents working on the TimeMachineTrimmer codebase. Read this file before making any changes.

## Project Overview

A macOS utility app that deletes Time Machine snapshots. Built with Swift + SwiftUI for macOS 14.4+, with a privileged XPC helper daemon running as root for privileged operations.

## Architecture

- **App**: TimeMachineTrimmer/ — SwiftUI views, view models, services
- **Helper**: PrivilegedHelper/ — XPC service daemon (`TimeMachineTrimmer-helper`)
- **Protocol**: HelperProtocol.swift — shared between app and helper (no `import AppKit` in helper)
- **Tests**: Tests/ — unit + integration test suite

### Key Naming

| Item             | Value                                                                    |
| ---------------- | ------------------------------------------------------------------------ |
| Helper binary    | `/usr/local/bin/TimeMachineTrimmer-helper`                               |
| Launchd label    | `com.ricardoleal.TimeMachineTrimmer.helper`                              |
| Launchd plist    | `/Library/LaunchDaemons/com.ricardoleal.TimeMachineTrimmer.helper.plist` |
| XPC Mach service | `com.ricardoleal.TimeMachineTrimmerHelper`                               |

## Workflow

- **Plan before build** — Always propose a detailed plan with files-to-modify and changes before writing any code. Get confirmation first to avoid wasted work.
- **Read first** — Before editing a file, read it fully. Before making changes, read all related files to understand the existing patterns.
- **For UI tasks** — Load the `macos-design` skill before writing any SwiftUI code. The skill provides references for layout & composition, interaction patterns, and visual design (light/dark mode, typography, color) to ensure native macOS feel. Read all three references before coding.
  - If the skill is not available, install it:
    ```bash
    git clone https://github.com/anomalyco/opencode-skills.git /tmp/opencode-skills
    cp -R /tmp/opencode-skills/macos-design ~/.agents/skills/
    rm -rf /tmp/opencode-skills
    ```

## Coding Conventions

### Swift & SwiftUI

- No comments in production code unless absolutely necessary
- Follow existing code style in the file you're editing
- Use `DebugLogger.log()` for logging, never `print()` (SwiftLint `no_print_statements` rule)
- Mark all `@Observable` classes with `@MainActor`
- Prefer `guard let` over `if let` where appropriate
- Use `\u{XXXX}` unicode escapes instead of emoji characters directly in strings (SwiftLint compatibility)
- Keep functions focused and single-purpose
- Use structured concurrency (`async/await`, `Task`, `Actor`) over GCD where possible

### Helper XPC

- Protocol defined in `HelperProtocol.swift`, shared between app target and helper
- XPC serialization uses native `[String: String]` and `[[String: String]]` types — **do NOT use `NSSecureCoding`** classes (they fail serialization across processes due to ObjC metatype mismatch)
- Reply dictionary: empty string `""` = success, non-empty = error message
- Helper process acts as XPC listener only — no CLI invocation for deletion
- Helper binary compiled separately with `swiftc` (not Xcode), module name `TMTHelper`

### macOS

- Minimum deployment target: macOS 14.4
- Ad-hoc code signing (`codesign --force --options runtime --sign -`)
- Helper installed via `osascript` with admin privileges, NOT `SMJobBless` (requires Apple Developer cert)
- Use `TMFDAUtils` for Full Disk Access permission checks
- Use `ByteCountFormatter` for size formatting (existing extension at `ByteCountFormatter+Extensions.swift`)

### tmutil / diskutil

- `tmutil deletebackups` verb does NOT exist on macOS 26 — do not use it
- Deletion strategy: `diskutil unmount force /path` then `diskutil apfs deleteSnapshot volume -uuid <uuid>`
- Use `$TMUTIL` environment variable for `tmutil` (defaults to `/usr/bin/tmutil`)

## Commands

| Action             | Command                   |
| ------------------ | ------------------------- |
| Build app + helper | `.scripts/build.sh`       |
| Build debug only   | `.scripts/build_debug.sh` |
| Lint               | `swiftlint --strict`      |
| Package DMG        | `.scripts/package_dmg.sh` |
| Run tests          | `.scripts/test.sh`        |

### Build requirements

- Must pass `swiftlint --strict` — **0 violations, 0 serious**
- Must compile with `swiftc` via `build.sh` (not Xcode for CI; Xcode project exists for local dev)
- Build produces `build/TimeMachineTrimmer.app`

## Project Structure

```
TimeMachineTrimmer/
  Models/           — Data models (TimeMachineBackup, BackupDestination)
  Services/         — TMUtilService, HelperClient, HelperProtocol, TMFDAUtils, DebugLogger
  ViewModels/       — BackupViewModel (main state machine)
  Views/            — SwiftUI views
  App entry         — TimeMachineTrimmerApp.swift
PrivilegedHelper/
  main.swift        — XPC listener + deletion logic
  CLI.swift         — CLI test tool for helper
  plist             — launchd plist
Tests/
  TestFramework.swift     — Assert helpers + shell() runner
  UnitTests.swift          — 27 unit tests
  IntegrationTests.swift   — 8 integration tests (skip if no helper)
  main.swift               — Test runner entry point
```

## Important Gotchas

- `Tests/` is excluded from SwiftLint (test code uses `print()` intentionally)
- The `BackupViewModel.deletionProgress` uses `-1` sentinel for indeterminate/indeterminate mode; `isBatchDeletion` flag controls the ProgressView display
- XPC has a 30s timeout guard via `ResumptionFlag` actor to prevent double-resume in `HelperClient`
- Privileged helper compiles `HelperProtocol.swift` from the **app source directory** (`$SRC_DIR/Services/HelperProtocol.swift`), not from `PrivilegedHelper/`
- When adding new Swift source files to the app target, update both `build.sh` (which globs `find "$SRC_DIR" -name "*.swift"`) AND `project.pbxproj`
- `AGENTS.md`, `.github/`, `.scripts/`, `build/`, `Tests/TEST-RESULTS.md` are documentation/infrastructure — do not reference in production code
- **Menu bar icon uses AppKit `NSStatusItem`** (via `MenuBarManager.swift`) — SwiftUI `MenuBarExtra(.menu)` does not render dropdown items on macOS 26.5.1 Tahoe. Do NOT use SwiftUI `MenuBarExtra` for the menu bar.

## Before Submitting Changes

1. Run `.scripts/build.sh` — must succeed
2. Run `swiftlint --strict` — must show "0 violations, 0 serious"
3. Run `.scripts/test.sh` — must pass (35/35 with helper, 27/27 without)
4. Verify no `opencode` references anywhere in project
5. Verify no `print()` in app code (SwiftLint catches this, but verify manually too)
6. Verify `PrivilegedHelper/main.swift` has no `import AppKit`
