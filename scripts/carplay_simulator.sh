#!/bin/bash
# Builds and installs DrivePlay in the iOS Simulator **with the CarPlay video
# entitlement**, so the CarPlay Simulator asks for the video surface and draws
# the picture the app plays.
#
#   usage: scripts/carplay_simulator.sh [simulator name]
#   env:   SIMULATOR_NAME, CARPLAY_CATEGORY
#
# The Simulator does not need Apple's grant: the entitlement lives in the app's
# Mach-O, so a build with CARPLAY_CATEGORY=video carries it. The **device**
# build stays on "audio" until the portal carries the CarPlay Video capability —
# a device build that asks for video does not sign.
#
# After this, attach the CarPlay Simulator in Xcode's Device Hub and tap
# "Screen Mirroring" on the car: the demo picture travels the same chain as a
# real share — capture, encode, serve, play.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

SIMULATOR_NAME="${1:-${SIMULATOR_NAME:-iPhone 18 Pro}}"
CARPLAY_CATEGORY="${CARPLAY_CATEGORY:-video}"

if [ "$CARPLAY_CATEGORY" != "video" ] && [ "$CARPLAY_CATEGORY" != "audio" ]; then
    echo "ERROR: CARPLAY_CATEGORY must be 'video' or 'audio', not '$CARPLAY_CATEGORY'."
    exit 1
fi

echo "Building for the Simulator with CARPLAY_CATEGORY=$CARPLAY_CATEGORY ..."
xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphonesimulator \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
  CARPLAY_CATEGORY="$CARPLAY_CATEGORY" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES \
  build || exit 1

APP="$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/CarTV-*/Build/Products/Debug-iphonesimulator/CarTV.app 2>/dev/null | head -1)"
if [ ! -d "$APP" ]; then
    echo "ERROR: the build produced no CarTV.app."
    exit 1
fi

# The two facts that decide what the car does: the entitlements file the build
# signed with, and the category the app tells CarPlay about.
echo "--- what the build carries ---"
xcodebuild -project CarTV.xcodeproj -scheme CarTV -sdk iphonesimulator \
  -configuration Debug \
  CARPLAY_CATEGORY="$CARPLAY_CATEGORY" \
  -showBuildSettings 2>/dev/null \
  | grep -E "^\s+(CODE_SIGN_ENTITLEMENTS|CARPLAY_CATEGORY) " \
  | sort -u
plutil -p "$APP/Info.plist" | grep CarPlayCategory

echo "--- installing ---"
xcrun simctl install booted "$APP" || exit 1
xcrun simctl launch booted com.rushabh.cartvv || exit 1

echo
echo "The app is running in the Simulator. Attach the CarPlay Simulator in"
echo "Xcode's Device Hub, then tap \"Screen Mirroring\" on the car."
