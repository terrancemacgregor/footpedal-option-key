#!/bin/bash

# Start the FootPedalOptionKey service

LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.periscoped.footpedal.plist"

if [ ! -f "$LAUNCH_AGENT" ]; then
    echo "Error: LaunchAgent not installed. Please run ./scripts/install.sh first."
    exit 1
fi

echo "Starting FootPedalOptionKey service..."

# Load the LaunchAgent
launchctl load "$LAUNCH_AGENT" 2>/dev/null || launchctl unload "$LAUNCH_AGENT" 2>/dev/null && launchctl load "$LAUNCH_AGENT"

echo ""
echo "Service started!"
echo ""
echo "To check status: ./scripts/status.sh"
echo "To view logs: tail -f /tmp/footpedal.log"
echo "To stop: ./scripts/stop.sh"
