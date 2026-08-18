#!/bin/bash
# Normalize the booted screenshot simulator before a capture session.
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <simulator-udid>" >&2
    exit 2
fi

UDID="$1"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" \
    --batteryState discharging --batteryLevel 100

echo "prepared simulator $UDID: light mode, 9:41, full signal, Wi-Fi, 100% battery"
