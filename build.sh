#!/bin/bash
set -e

echo "🔨 Building Pasteboard without Xcode..."

# Configuration
APP_NAME="Pasteboard"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean previous build
rm -rf "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "📦 Compiling Swift sources..."

# Compile all Swift files into a single executable
swiftc -o "$MACOS_DIR/$APP_NAME" \
    -sdk $(xcrun --show-sdk-path) \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    -framework CoreServices \
    -framework Carbon \
    OmniClip/OmniClipApp.swift \
    OmniClip/AppDelegate.swift \
    OmniClip/AppSettings.swift \
    OmniClip/ClipItem.swift \
    OmniClip/ClipboardManager.swift \
    OmniClip/ScreenshotWatcher.swift \
    OmniClip/ContentView.swift \
    OmniClip/ClipItemRow.swift \
    OmniClip/PreviewPanel.swift \
    OmniClip/SettingsView.swift

echo "📋 Copying resources..."

# Copy Info.plist
cp OmniClip/Info.plist "$CONTENTS_DIR/"

# Create iconset and convert to icns
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_16x16.png "$ICONSET_DIR/icon_16x16.png"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_16x16@2x.png "$ICONSET_DIR/icon_16x16@2x.png"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_32x32.png "$ICONSET_DIR/icon_32x32.png"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_32x32@2x.png "$ICONSET_DIR/icon_32x32@2x.png"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_128x128.png "$ICONSET_DIR/icon_128x128.png"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png "$ICONSET_DIR/icon_128x128@2x.png"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_256x256.png "$ICONSET_DIR/icon_256x256.png"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png "$ICONSET_DIR/icon_256x256@2x.png"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_512x512.png "$ICONSET_DIR/icon_512x512.png"
cp OmniClip/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# Copy menu bar icon
cp OmniClip/Assets.xcassets/MenuBarIcon.imageset/menubar_icon.png "$RESOURCES_DIR/menubar_icon.png"
cp OmniClip/Assets.xcassets/MenuBarIcon.imageset/menubar_icon@2x.png "$RESOURCES_DIR/menubar_icon@2x.png"

# Copy Assets (we'll create a simple one)
mkdir -p "$RESOURCES_DIR/Assets.xcassets"

# Create PkgInfo
echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

echo "🔐 Signing app..."
codesign --force --deep --sign - --entitlements OmniClip/OmniClip.entitlements "$APP_BUNDLE" 2>/dev/null || echo "⚠️  Code signing skipped (optional)"

echo "✅ Build complete!"
echo "📍 App location: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
