#!/bin/bash

# Install FootPedalOptionKey

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/FootPedalOptionKey.app"
INSTALL_PATH="/Applications/FootPedalOptionKey.app"
LAUNCH_AGENT_SRC="$PROJECT_DIR/LaunchAgents/com.periscoped.footpedal.plist"
LAUNCH_AGENT_DST="$HOME/Library/LaunchAgents/com.periscoped.footpedal.plist"

echo "Installing FootPedalOptionKey..."
echo ""

# Check if app bundle exists
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: App bundle not found. Please run ./scripts/build.sh first."
    exit 1
fi

# Stop existing service if running
if launchctl list 2>/dev/null | grep -q "com.periscoped.footpedal"; then
    echo "Stopping existing service..."
    launchctl unload "$LAUNCH_AGENT_DST" 2>/dev/null || true
fi

# Kill any running instances
pkill -f FootPedalOptionKey 2>/dev/null || true

# Install app bundle
echo "Installing app to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

# Install LaunchAgent
echo "Installing LaunchAgent..."
mkdir -p "$HOME/Library/LaunchAgents"
cp "$LAUNCH_AGENT_SRC" "$LAUNCH_AGENT_DST"

echo ""
echo "Installation complete!"
echo ""
echo "==================================="
echo "IMPORTANT: Permission Setup Required"
echo "==================================="
echo ""
echo "Before starting the service, you MUST grant permissions:"
echo ""
echo "1. Open System Settings -> Privacy & Security -> Accessibility"
echo "2. Click the '+' button"
echo "3. Navigate to /Applications/FootPedalOptionKey.app"
echo "4. Add the application and ensure it's toggled ON"
echo ""
echo "After granting permissions, run:"
echo "  ./scripts/start.sh"
echo ""
