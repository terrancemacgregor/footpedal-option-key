#!/bin/bash

# Uninstall FootPedalOptionKey

INSTALL_PATH="/Applications/FootPedalOptionKey.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.periscoped.footpedal.plist"
CONFIG_DIR="$HOME/.config/footpedal"

echo "Uninstalling FootPedalOptionKey..."
echo ""

# Stop service
if launchctl list 2>/dev/null | grep -q "com.periscoped.footpedal"; then
    echo "Stopping service..."
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
fi

# Kill any running instances
pkill -f FootPedalOptionKey 2>/dev/null || true

# Remove LaunchAgent
if [ -f "$LAUNCH_AGENT" ]; then
    echo "Removing LaunchAgent..."
    rm "$LAUNCH_AGENT"
fi

# Remove app bundle
if [ -d "$INSTALL_PATH" ]; then
    echo "Removing app..."
    rm -rf "$INSTALL_PATH"
fi

# Ask about config
if [ -d "$CONFIG_DIR" ]; then
    read -p "Remove configuration files? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        echo "Configuration removed."
    fi
fi

echo ""
echo "Uninstallation complete!"
echo ""
echo "Note: You may want to remove the app from:"
echo "  System Settings -> Privacy & Security -> Accessibility"
