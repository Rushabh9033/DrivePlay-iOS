#!/bin/bash
# Installs the latest device build of DrivePlay on a connected iPhone.
#
#   usage: scripts/auto_install.sh [udid]
#   env:   DEVICE_UDID, APP_PATH, WAIT_SECONDS
#
# Nothing about the machine or the phone is hardcoded: the device is picked at
# run time and the .app is located in DerivedData. The wait is bounded, so a
# missing phone ends in an error instead of an endless loop.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

WAIT_SECONDS="${WAIT_SECONDS:-300}"
DEVICE_UDID="${1:-${DEVICE_UDID:-}}"

# The UDID of the first connected *physical* device (simulators are skipped).
detect_udid() {
    xcrun devicectl list devices --json-output - 2>/dev/null | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)["result"]["devices"]
except Exception:
    sys.exit(0)
for device in devices:
    if device.get("visibilityClass") == "simulators":
        continue
    props = device.get("properties", {})
    udid = props.get("hardware", {}).get("udid")
    if udid and props.get("connection", {}).get("state") == "connected":
        print(udid)
        break
'
}

# The app is located in DerivedData unless APP_PATH says otherwise.
resolve_app() {
    if [ -n "${APP_PATH:-}" ]; then
        echo "$APP_PATH"
        return
    fi
    ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/CarTV-*/Build/Products/*-iphoneos/CarTV.app 2>/dev/null | head -1
}

APP="$(resolve_app)"
if [ ! -d "$APP" ]; then
    echo "ERROR: no built CarTV.app found."
    echo "       build one first:"
    echo "         xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphoneos -configuration Debug build"
    echo "       or point APP_PATH at an existing build."
    exit 1
fi

if [ -z "$DEVICE_UDID" ] && ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is needed to detect the device. Pass the udid: scripts/auto_install.sh <udid>"
    exit 1
fi

deadline=$(( $(date +%s) + WAIT_SECONDS ))
while :; do
    if [ -z "$DEVICE_UDID" ]; then
        DEVICE_UDID="$(detect_udid)"
    fi

    if [ -n "$DEVICE_UDID" ]; then
        echo "Installing $(basename "$APP") on $DEVICE_UDID ..."
        if xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"; then
            echo "SUCCESS: installed on $DEVICE_UDID"
            exit 0
        fi
        echo "install failed; retrying in 3s"
    else
        echo "waiting for a connected iPhone ..."
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "ERROR: no device available after ${WAIT_SECONDS}s."
        echo "       connect the iPhone and trust this Mac, or pass a udid: scripts/auto_install.sh <udid>"
        exit 1
    fi
    sleep 3
done
