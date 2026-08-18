#!/bin/bash
# Capture the same image as the simulator's hardware-button screenshot.
# Unlike `simctl io screenshot`, this path does not bake a Dynamic Island pill
# into the framebuffer. macOS will request Accessibility permission the first
# time System Events controls Simulator's Device menu.
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <simulator-udid> <output.png>" >&2
    exit 2
fi

UDID="$1"
OUT="$2"
DCIM="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Media/DCIM/100APPLE"
mkdir -p "$(dirname "$OUT")"

BEFORE=$(ls -t "$DCIM"/*.PNG 2>/dev/null | head -1 || echo none)
osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1
sleep 0.6
osascript -e 'tell application "System Events" to tell process "Simulator" to click menu item "Trigger Screenshot" of menu 1 of menu bar item "Device" of menu bar 1' >/dev/null

for _ in $(seq 1 25); do
    sleep 0.4
    LATEST=$(ls -t "$DCIM"/*.PNG 2>/dev/null | head -1 || echo none)
    if [ "$LATEST" != "$BEFORE" ]; then
        cp "$LATEST" "$OUT"
        sleep 7
        echo "saved: $OUT"
        exit 0
    fi
done

echo "failed: no new simulator screenshot appeared in $DCIM" >&2
exit 1
