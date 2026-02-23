#!/bin/bash

# StreamDeck: Stop and fully uninstall WhisperFoot
# When launched from StreamDeck, opens a Terminal window to show progress.

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# If launched outside Terminal (e.g. from StreamDeck), relaunch in Terminal
if [ "$WHISPERFOOT_IN_TERMINAL" != "1" ]; then
    osascript -e "display notification \"Stopping and uninstalling WhisperFoot\" with title \"WhisperFoot\""
    osascript -e "tell application \"Terminal\"
        activate
        do script \"export WHISPERFOOT_IN_TERMINAL=1 && '$0'\"
    end tell"
    exit 0
fi

# -- Running in Terminal from here --

INSTALL_PATH="/Applications/WhisperFoot.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.periscoped.footpedal.plist"
CONFIG_DIR="$HOME/.config/footpedal"

echo "==========================="
echo "WhisperFoot: Stop & Uninstall"
echo "==========================="
echo ""

echo "Stopping service..."
if launchctl list 2>/dev/null | grep -q "com.periscoped.footpedal"; then
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    echo "  Unloaded LaunchAgent"
else
    echo "  Service not running"
fi
echo ""

echo "Killing running processes..."
if pgrep -f WhisperFoot > /dev/null 2>&1; then
    pkill -f WhisperFoot 2>/dev/null || true
    echo "  Killed WhisperFoot process"
else
    echo "  No running process found"
fi
echo ""

echo "Removing LaunchAgent..."
if [ -f "$LAUNCH_AGENT" ]; then
    rm -f "$LAUNCH_AGENT"
    echo "  Removed $LAUNCH_AGENT"
else
    echo "  Not found (skipped)"
fi
echo ""

echo "Removing installed app..."
if [ -d "$INSTALL_PATH" ]; then
    rm -rf "$INSTALL_PATH"
    echo "  Removed $INSTALL_PATH"
else
    echo "  Not found (skipped)"
fi
echo ""

echo "Removing log files..."
if [ -f /tmp/footpedal.log ]; then
    rm -f /tmp/footpedal.log
    echo "  Removed /tmp/footpedal.log"
else
    echo "  /tmp/footpedal.log not found (skipped)"
fi
if [ -f /tmp/footpedal.error.log ]; then
    rm -f /tmp/footpedal.error.log
    echo "  Removed /tmp/footpedal.error.log"
else
    echo "  /tmp/footpedal.error.log not found (skipped)"
fi
echo ""

echo "Removing config..."
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo "  Removed $CONFIG_DIR"
else
    echo "  Not found (skipped)"
fi
echo ""

echo "Removing Accessibility permission..."
tccutil reset Accessibility com.periscoped.footpedal 2>/dev/null
echo "  Reset Accessibility permission for com.periscoped.footpedal"
echo ""

echo "==========================="
echo "Uninstall complete!"
echo "==========================="
