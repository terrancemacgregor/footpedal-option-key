#!/bin/bash

# Stop the FootPedalOptionKey service

LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.periscoped.footpedal.plist"

if [ ! -f "$LAUNCH_AGENT" ]; then
    echo "LaunchAgent not installed."
    exit 0
fi

echo "Stopping FootPedalOptionKey service..."

launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true

echo "Service stopped."
