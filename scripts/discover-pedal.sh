#!/bin/bash

# Foot Pedal Discovery Script
# Helps identify the Vendor ID and Product ID of your USB foot pedal

echo "==================================="
echo "USB Foot Pedal Discovery Tool"
echo "==================================="
echo ""
echo "This script helps you find your foot pedal's Vendor ID and Product ID."
echo ""
echo "Instructions:"
echo "1. Make sure your foot pedal is DISCONNECTED"
echo "2. Press Enter when ready..."
read

echo "Capturing current USB devices..."
BEFORE=$(ioreg -p IOUSB -l | grep -E '"USB Vendor Name"|"USB Product Name"|"idVendor"|"idProduct"')

echo ""
echo "Now CONNECT your foot pedal and press Enter..."
read

echo "Scanning for new devices..."
AFTER=$(ioreg -p IOUSB -l | grep -E '"USB Vendor Name"|"USB Product Name"|"idVendor"|"idProduct"')

echo ""
echo "==================================="
echo "New USB Device(s) Detected:"
echo "==================================="

# Show the difference
diff <(echo "$BEFORE") <(echo "$AFTER") | grep ">" | sed 's/> //'

echo ""
echo "==================================="
echo ""
echo "You can also see detailed HID information below:"
echo ""

# Get more detailed HID info
ioreg -p IOUSB -l -w 0 | grep -A 20 -i "foot\|pedal\|ikkegol\|keyboard" | head -50

echo ""
echo "==================================="
echo "Alternative method - System Profiler:"
echo "==================================="
echo ""

system_profiler SPUSBDataType 2>/dev/null | grep -A 10 -i "foot\|pedal\|ikkegol" | head -30

echo ""
echo "==================================="
echo ""
echo "Once you have your Vendor ID (idVendor) and Product ID (idProduct),"
echo "you can configure them by running:"
echo ""
echo "  ./scripts/configure-pedal.sh <vendorID> <productID>"
echo ""
echo "For example, if idVendor = 0x1a86 and idProduct = 0xe026:"
echo "  ./scripts/configure-pedal.sh 0x1a86 0xe026"
echo ""
