#!/bin/bash

# Build the FootPedalOptionKey application

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/FootPedalOptionKey.app"

cd "$PROJECT_DIR"

echo "Building FootPedalOptionKey..."
echo ""

# Build in release mode
swift build -c release

# Create app bundle
echo "Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"

# Copy binary
cp "$PROJECT_DIR/.build/release/FootPedalOptionKey" "$APP_BUNDLE/Contents/MacOS/"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FootPedalOptionKey</string>
    <key>CFBundleIdentifier</key>
    <string>com.periscoped.footpedal</string>
    <key>CFBundleName</key>
    <string>FootPedalOptionKey</string>
    <key>CFBundleDisplayName</key>
    <string>Foot Pedal Option Key</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Sign the app bundle
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Build complete!"
echo ""
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To install, run: ./scripts/install.sh"
