#!/bin/bash

# Configure the foot pedal Vendor ID and Product ID

if [ $# -ne 2 ]; then
    echo "Usage: $0 <vendorID> <productID>"
    echo ""
    echo "Examples:"
    echo "  $0 0x1a86 0xe026    # Hex format"
    echo "  $0 6790 57382       # Decimal format"
    echo ""
    echo "Run ./scripts/discover-pedal.sh to find your device's IDs"
    exit 1
fi

VID=$1
PID=$2

# Convert hex to decimal if needed
if [[ $VID == 0x* ]]; then
    VID=$((VID))
fi
if [[ $PID == 0x* ]]; then
    PID=$((PID))
fi

CONFIG_DIR="$HOME/.config/footpedal"
CONFIG_FILE="$CONFIG_DIR/config.json"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << EOF
{
    "vendorID": $VID,
    "productID": $PID
}
EOF

echo "Configuration saved to $CONFIG_FILE"
echo ""
echo "Contents:"
cat "$CONFIG_FILE"
echo ""
echo ""
echo "You can now run the foot pedal application."
