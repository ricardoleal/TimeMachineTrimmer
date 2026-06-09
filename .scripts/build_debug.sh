#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$PROJECT_DIR/TimeMachineTrimmer"
APP_NAME="TimeMachineTrimmer"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BINARY_PATH="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
MANIFEST="$BUILD_DIR/.source_manifest"
ENTITLEMENTS="$SRC_DIR/$APP_NAME.entitlements"

# Pick signing identity: Apple Development cert > ad-hoc
SIGN_IDENTITY="-"
APPLE_DEV_CERT=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
if [ -n "$APPLE_DEV_CERT" ]; then
    SIGN_IDENTITY="$APPLE_DEV_CERT"
    echo "==> Signing identity: $SIGN_IDENTITY"
fi

# Compute collective source checksum
CURRENT_HASH="$(find "$SRC_DIR" -name "*.swift" -exec md5 -r {} + | sort | md5 -r | cut -d' ' -f1)"

# Check if any source changed
NEEDS_BUILD=true
if [ -f "$BINARY_PATH" ] && [ -f "$MANIFEST" ]; then
    OLD_HASH="$(cat "$MANIFEST")"
    if [ "$OLD_HASH" = "$CURRENT_HASH" ]; then
        NEEDS_BUILD=false
        echo "✅ No source changes — using existing binary."
    fi
fi

if $NEEDS_BUILD; then
    echo "==> Compiling Swift sources (DEBUG)..."
    TEMP_BINARY=$(mktemp /tmp/"$APP_NAME".XXXXXX)
    find "$SRC_DIR" -name "*.swift" -print0 | xargs -0 swiftc \
      -target arm64-apple-macosx14.4 \
      -sdk "$(xcrun --show-sdk-path)" \
      -o "$TEMP_BINARY" \
      -module-name "$APP_NAME" \
      -emit-executable \
      -g

    mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
    cp "$TEMP_BINARY" "$BINARY_PATH"
    rm -f "$TEMP_BINARY"

    cp "$SRC_DIR/Info.plist" "$APP_BUNDLE/Contents/"
    echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

    # Generate app icon from SVG
    echo "==> Generating app icon..."
    SVG_SOURCE="$SRC_DIR/Assets.xcassets/AppIcon.svg"
    ICONSET_TMP="/tmp/tmt_iconset_$$.iconset"
    rm -rf "$ICONSET_TMP"
    mkdir -p "$ICONSET_TMP"
    # SVG has 400x400 viewBox — --width=N renders at exact N×N pixels
    rsvg-convert --width=16   "$SVG_SOURCE" -o "$ICONSET_TMP/icon_16x16.png"
    rsvg-convert --width=32   "$SVG_SOURCE" -o "$ICONSET_TMP/icon_16x16@2x.png"
    rsvg-convert --width=32   "$SVG_SOURCE" -o "$ICONSET_TMP/icon_32x32.png"
    rsvg-convert --width=64   "$SVG_SOURCE" -o "$ICONSET_TMP/icon_32x32@2x.png"
    rsvg-convert --width=128  "$SVG_SOURCE" -o "$ICONSET_TMP/icon_128x128.png"
    rsvg-convert --width=256  "$SVG_SOURCE" -o "$ICONSET_TMP/icon_128x128@2x.png"
    rsvg-convert --width=256  "$SVG_SOURCE" -o "$ICONSET_TMP/icon_256x256.png"
    rsvg-convert --width=512  "$SVG_SOURCE" -o "$ICONSET_TMP/icon_256x256@2x.png"
    rsvg-convert --width=512  "$SVG_SOURCE" -o "$ICONSET_TMP/icon_512x512.png"
    rsvg-convert --width=1024 "$SVG_SOURCE" -o "$ICONSET_TMP/icon_512x512@2x.png"
    cat > "$ICONSET_TMP/Contents.json" << 'ICONEOF'
{
  "images" : [
    { "size":"16x16", "idiom":"mac", "filename":"icon_16x16.png", "scale":"1x" },
    { "size":"16x16", "idiom":"mac", "filename":"icon_16x16@2x.png", "scale":"2x" },
    { "size":"32x32", "idiom":"mac", "filename":"icon_32x32.png", "scale":"1x" },
    { "size":"32x32", "idiom":"mac", "filename":"icon_32x32@2x.png", "scale":"2x" },
    { "size":"128x128", "idiom":"mac", "filename":"icon_128x128.png", "scale":"1x" },
    { "size":"128x128", "idiom":"mac", "filename":"icon_128x128@2x.png", "scale":"2x" },
    { "size":"256x256", "idiom":"mac", "filename":"icon_256x256.png", "scale":"1x" },
    { "size":"256x256", "idiom":"mac", "filename":"icon_256x256@2x.png", "scale":"2x" },
    { "size":"512x512", "idiom":"mac", "filename":"icon_512x512.png", "scale":"1x" },
    { "size":"512x512", "idiom":"mac", "filename":"icon_512x512@2x.png", "scale":"2x" }
  ],
  "info" : { "author" : "developer", "version" : 1 }
}
ICONEOF
    iconutil -c icns "$ICONSET_TMP" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>&1
    rm -rf "$ICONSET_TMP"

    echo "==> Build complete."
fi

# Always re-sign (cached binary may have stale/adhoc signature)
echo "==> Code-signing with hardened runtime (identity: $SIGN_IDENTITY)..."
codesign --force --options runtime --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
codesign -dv "$APP_BUNDLE" 2>&1 | grep -E "Signature|Signed|adhoc|TeamIdentifier"

if $NEEDS_BUILD; then
    echo "$CURRENT_HASH" > "$MANIFEST"
    echo "✅ Build & sign complete."
fi

echo ""
echo "App: $BINARY_PATH"
