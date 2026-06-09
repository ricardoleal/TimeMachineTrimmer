#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_DIR/TimeMachineTrimmer"
APP_NAME="TimeMachineTrimmer"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

echo "==> Compiling Swift sources..."
find "$SRC_DIR" -name "*.swift" -print0 | xargs -0 swiftc \
  -target arm64-apple-macosx14.4 \
  -sdk "$(xcrun --show-sdk-path)" \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
  -module-name "$APP_NAME" \
  -emit-executable \
  -O

echo "==> Compiling privileged helper..."
HELPER_DIR="$PROJECT_DIR/PrivilegedHelper"
mkdir -p "$APP_BUNDLE/Contents/Library/LaunchServices"
swiftc \
  -target arm64-apple-macosx14.4 \
  -sdk "$(xcrun --show-sdk-path)" \
  "$HELPER_DIR/main.swift" \
  "$SRC_DIR/Services/HelperProtocol.swift" \
  -o "$APP_BUNDLE/Contents/Library/LaunchServices/TimeMachineTrimmer-helper" \
  -module-name "TMTHelper" \
  -emit-executable \
  -O

echo "==> Copying helper launchd plist..."
cp "$HELPER_DIR/com.ricardoleal.TimeMachineTrimmer.helper.plist" "$APP_BUNDLE/Contents/Library/LaunchServices/"

echo "==> Copying Info.plist..."
cp "$SRC_DIR/Info.plist" "$APP_BUNDLE/Contents/"

echo "==> Creating PkgInfo..."
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "==> Code-signing helper with hardened runtime (ad-hoc)..."
codesign --force --options runtime --sign - "$APP_BUNDLE/Contents/Library/LaunchServices/TimeMachineTrimmer-helper"

echo "==> Code-signing app with hardened runtime (ad-hoc)..."
codesign --force --options runtime --sign - --entitlements "$SRC_DIR/$APP_NAME.entitlements" "$APP_BUNDLE"

echo ""
echo "✅ Build complete: $APP_BUNDLE"
echo ""
echo "To run: open \"$APP_BUNDLE\""
