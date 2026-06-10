#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_RUNNER="$PROJECT_DIR/build/TimeMachineTrimmer-tests"
CLI_TOOL="/tmp/TimeMachineTrimmer-helper-cli"

# Build CLI tool for integration tests
if [ ! -f "$CLI_TOOL" ]; then
  ENTRY_FILE=/tmp/main.swift
  if ! grep -q "CLI.main" "$ENTRY_FILE" 2>/dev/null; then
    printf 'import Foundation\nCLI.main()\n' > "$ENTRY_FILE"
  fi
  echo "==> Building CLI tool..."
  swiftc \
    "$ENTRY_FILE" \
    "$PROJECT_DIR/PrivilegedHelper/CLI.swift" \
    "$PROJECT_DIR/TimeMachineTrimmer/Services/HelperProtocol.swift" \
    -o "$CLI_TOOL" \
    -target arm64-apple-macosx14.4 \
    -sdk "$(xcrun --show-sdk-path)" \
    -emit-executable \
    -O
fi

echo "==> Compiling test sources..."
find "$PROJECT_DIR/Tests" -name "*.swift" -print0 | xargs -0 swiftc \
  -target arm64-apple-macosx14.4 \
  -sdk "$(xcrun --show-sdk-path)" \
  -o "$TEST_RUNNER" \
  -emit-executable \
  -O

echo ""
echo "==> Running tests..."
"$TEST_RUNNER"
