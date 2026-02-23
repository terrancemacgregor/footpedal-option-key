#!/bin/bash

# Check status of FootPedalOptionKey service

echo "FootPedalOptionKey Status"
echo "========================="
echo ""

# Check if LaunchAgent is loaded
if launchctl list 2>/dev/null | grep -q "com.periscoped.footpedal"; then
    echo "Service: RUNNING"
    launchctl list 2>/dev/null | grep "com.periscoped.footpedal"
else
    echo "Service: NOT RUNNING"
fi

echo ""

# Check for running process
if pgrep -f FootPedalOptionKey > /dev/null; then
    echo "Process: RUNNING"
    ps aux | grep FootPedalOptionKey | grep -v grep
else
    echo "Process: NOT RUNNING"
fi

echo ""
echo "Recent log output:"
echo "------------------"
if [ -f /tmp/footpedal.log ]; then
    tail -20 /tmp/footpedal.log
else
    echo "(No log file found)"
fi

echo ""
echo "Recent errors:"
echo "--------------"
if [ -f /tmp/footpedal.error.log ]; then
    tail -10 /tmp/footpedal.error.log
else
    echo "(No error log found)"
fi
