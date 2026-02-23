#!/bin/bash

# StreamDeck: Build, install, and start WhisperFoot
# When launched from StreamDeck, opens a Terminal window to show progress.

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# If launched outside Terminal (e.g. from StreamDeck), relaunch in Terminal
if [ "$WHISPERFOOT_IN_TERMINAL" != "1" ]; then
    osascript -e "display notification \"Building and installing WhisperFoot\" with title \"WhisperFoot\""
    osascript -e "tell application \"Terminal\"
        activate
        do script \"export WHISPERFOOT_IN_TERMINAL=1 && '$0'\"
    end tell"
    exit 0
fi

# -- Running in Terminal from here --

set -e

APP_BUNDLE="$PROJECT_DIR/output/WhisperFoot.app"
INSTALL_PATH="/Applications/WhisperFoot.app"
LAUNCH_AGENT_SRC="$PROJECT_DIR/launchagents/com.periscoped.footpedal.plist"
LAUNCH_AGENT_DST="$HOME/Library/LaunchAgents/com.periscoped.footpedal.plist"

echo "==========================="
echo "WhisperFoot: Build & Install"
echo "==========================="
echo ""

# ---- Stop existing instance ----
echo "Stopping existing instance..."
if launchctl list 2>/dev/null | grep -q "com.periscoped.footpedal"; then
    launchctl unload "$LAUNCH_AGENT_DST" 2>/dev/null || true
    echo "  Unloaded LaunchAgent"
else
    echo "  No existing service running"
fi
if pgrep -f WhisperFoot > /dev/null 2>&1; then
    pkill -f WhisperFoot 2>/dev/null || true
    echo "  Killed WhisperFoot process"
else
    echo "  No running process found"
fi
echo ""

# ---- Build ----
echo "Compiling Swift (release mode)..."
cd "$PROJECT_DIR"
swift build -c release
echo "  Build succeeded"
echo ""

echo "Creating app bundle..."
mkdir -p "$PROJECT_DIR/output"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$PROJECT_DIR/.build/release/FootPedalOptionKey" "$APP_BUNDLE/Contents/MacOS/WhisperFoot"
echo "  Copied binary to $APP_BUNDLE/Contents/MacOS/WhisperFoot"

cp "$PROJECT_DIR/resources/"*.png "$APP_BUNDLE/Contents/Resources/"
cp "$PROJECT_DIR/resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
echo "  Copied resources (icons)"

GIT_VERSION=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
echo "$GIT_VERSION" > "$APP_BUNDLE/Contents/Resources/version.txt"
echo "  Embedded git version: $GIT_VERSION"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>WhisperFoot</string>
    <key>CFBundleIdentifier</key>
    <string>com.periscoped.footpedal</string>
    <key>CFBundleName</key>
    <string>WhisperFoot</string>
    <key>CFBundleDisplayName</key>
    <string>WhisperFoot</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
echo "  Generated Info.plist"

codesign --force --deep --sign "Terrance-MacGregor-Local-CodeSign" "$APP_BUNDLE"
echo "  Code signed app bundle"
echo ""

# ---- Install ----
echo "Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"
echo "  Copied app to $INSTALL_PATH"
echo ""

echo "Installing LaunchAgent..."
mkdir -p "$HOME/Library/LaunchAgents"
cp "$LAUNCH_AGENT_SRC" "$LAUNCH_AGENT_DST"
echo "  Copied to $LAUNCH_AGENT_DST"
echo ""

# ---- Verify LaunchAgent plist ----
echo "Verifying LaunchAgent plist..."
EXPECTED_PATH="/Applications/WhisperFoot.app/Contents/MacOS/WhisperFoot"
ACTUAL_PATH=$(defaults read "$LAUNCH_AGENT_DST" ProgramArguments 2>/dev/null | grep -o '/[^"]*' | head -1)
if [ "$ACTUAL_PATH" != "$EXPECTED_PATH" ]; then
    echo "  ERROR: LaunchAgent points to wrong path: $ACTUAL_PATH"
    echo "  Expected: $EXPECTED_PATH"
    echo "  Fixing launchagents/com.periscoped.footpedal.plist in repo..."
    exit 1
else
    echo "  LaunchAgent path is correct: $EXPECTED_PATH"
fi
echo ""

# ---- Start ----
echo "Starting service..."
launchctl load "$LAUNCH_AGENT_DST" 2>/dev/null || (launchctl unload "$LAUNCH_AGENT_DST" 2>/dev/null && launchctl load "$LAUNCH_AGENT_DST")
sleep 1

if pgrep -f WhisperFoot > /dev/null 2>&1; then
    PID=$(pgrep -f WhisperFoot)
    echo "  WhisperFoot is running (PID $PID)"
else
    echo "  WARNING: WhisperFoot is not running!"
    echo "  Check /tmp/footpedal.error.log for details"
    echo "  You may need to grant Accessibility permissions:"
    echo "    System Settings -> Privacy & Security -> Accessibility"
    echo "    Add /Applications/WhisperFoot.app"
fi
echo ""

echo "==========================="
echo "Build & Install complete!"
echo "==========================="
