#!/bin/bash
# Runs the whole test suite the way it has to be run.
#
#   scripts/run_tests.sh [extra xcodebuild arguments]
#
# The Simulator build is signed ad-hoc: an unsigned app has no
# application-identifier, so the Keychain refuses every write (-34018) and the
# credential tests cannot pass.
#
# The Simulator is chosen automatically; set SIMULATOR to override it.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

if [ -z "${SIMULATOR:-}" ]; then
    if xcrun simctl list devices available | grep -q "iPhone 18 Pro"; then
        SIMULATOR="iPhone 18 Pro"
    else
        SIMULATOR=$(xcrun simctl list devices available \
            | grep -oE 'iPhone [^()]+' | head -1 | sed 's/[[:space:]]*$//')
    fi
fi

if [ -z "$SIMULATOR" ]; then
    echo "No iPhone Simulator found. Set SIMULATOR to a device name." >&2
    exit 1
fi

echo "Testing on: $SIMULATOR"

xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES \
    "$@" test
