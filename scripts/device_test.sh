#!/bin/bash
# Waits for the physical iPhone and runs the test suite on it.
#
# The phone is the only place the CarPlay video surface and the broadcast can be
# exercised for real, and Xcode 27's CarPlay Simulator hosts **physical devices
# only** — so the tests belong on the phone.
#
# The phone is picked by its name, not by a hardcoded id: it is found among the
# connected devices, so the script keeps working when the id changes.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

DEVICE_NAME="${DEVICE_NAME:-Rushabh}"
WAIT_SECONDS="${WAIT_SECONDS:-3600}"

echo "waiting for the phone ($DEVICE_NAME) …"

udid=""
deadline=$(( $(date +%s) + WAIT_SECONDS ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    # devicectl reports the state, but it is not the only truth: a phone that
    # is plugged in shows up as "available (paired)" there while it is
    # "connected" — so the USB list (libimobiledevice) is asked as well.
    line=$(xcrun devicectl list devices 2>/dev/null | grep -i "$DEVICE_NAME" | head -1)
    if printf '%s' "$line" | grep -qE "connected|available"; then
        udid=$(printf '%s' "$line" | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
        [ -n "$udid" ] && break
    fi
    sleep 10
done

if [ -z "$udid" ]; then
    echo "the phone never showed up — nothing was tested"
    exit 1
fi

echo "phone found: $udid — running the tests"

xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphoneos \
    -destination "id=$udid" -configuration Debug \
    CARPLAY_CATEGORY=video \
    test 2>&1 | tee "${LOG_FILE:-build/device_test.log}" \
    | grep -E "Test Case .*(passed|failed)|Executed .* tests|error:|\*\* TEST"
