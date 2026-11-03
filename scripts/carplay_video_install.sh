#!/bin/bash
# Installs the CarPlay **video** build on the phone.
#
#   usage: scripts/carplay_video_install.sh [path/to/*.mobileprovision]
#
# Apple mints the provisioning profile that carries
# `com.apple.developer.carplay-video`. With the Apple account signed in on
# this machine, **Xcode does that itself** during the build
# (`-allowProvisioningUpdates`), so this script needs no downloaded profile:
#
#   1. find a profile that already carries the entitlement (the argument, the
#      newest one in ~/Downloads, or one already installed) and check it
#   2. install it where Xcode looks, moving the profile it replaces aside so
#      Xcode cannot pick the wrong one
#   3. build for the connected phone with CARPLAY_CATEGORY=video
#   4. print the entitlements the app was actually signed with
#   5. install it on the phone
#
# Signing stays on **automatic**, which is what the project uses: Xcode signs
# with the profile that matches the app id and the entitlements it finds
# locally — minting one first if the account is signed in.
#
# Nothing about the machine is hardcoded: the profile is found by its
# contents, and the phone at run time.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

APP_ID="com.rushabh.cartvv"
TEAM_ID="47T499AR2T"
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
DOWNLOADS="$HOME/Downloads"

# --- find the profile ------------------------------------------------------

# The app id of the profile: the one that names our bundle id.
app_id_of() {
    /usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$1" 2>/dev/null
}

# True when the profile is ours and carries the CarPlay video entitlement.
is_video_profile() {
    local plist="$1" appid video
    appid="$(app_id_of "$plist")"
    video="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.carplay-video" "$plist" 2>/dev/null)"
    [ "$appid" = "$TEAM_ID.$APP_ID" ] && [ "$video" = "true" ]
}

decode() {
    security cms -D -i "$1" > "$2" 2>/dev/null
}

find_profile() {
    local candidate plist
    # 1. the one that was named on the command line
    if [ -n "${1:-}" ]; then
        echo "$1"
        return 0
    fi
    # 2. the newest one in ~/Downloads
    for candidate in $(ls -t "$DOWNLOADS"/*.mobileprovision 2>/dev/null); do
        plist="$(mktemp -t carplay-video)"
        if decode "$candidate" "$plist" && is_video_profile "$plist"; then
            rm -f "$plist"
            echo "$candidate"
            return 0
        fi
        rm -f "$plist"
    done
    # 3. one that is already installed
    for candidate in "$PROFILE_DIR"/*.mobileprovision; do
        [ -f "$candidate" ] || continue
        plist="$(mktemp -t carplay-video)"
        if decode "$candidate" "$plist" && is_video_profile "$plist"; then
            rm -f "$plist"
            echo "$candidate"
            return 0
        fi
        rm -f "$plist"
    done
    return 1
}

PROFILE="$(find_profile "${1:-}")"
if [ -z "$PROFILE" ]; then
    # No profile yet — that is not a dead end. With the Apple account signed
    # in on this machine, Xcode mints the profile itself while it builds
    # (`-allowProvisioningUpdates`), so the build below does the work. The
    # account has to be signed in; nothing else is needed.
    echo "No local profile carries com.apple.developer.carplay-video yet."
    echo "Xcode will mint one during the build — the Apple account has to be signed in."
else
    PROFILE_PLIST="$(mktemp -t carplay-video-plist)"
    decode "$PROFILE" "$PROFILE_PLIST" || { echo "The profile could not be decoded."; exit 1; }

    echo "Profile: $(/usr/libexec/PlistBuddy -c "Print :Name" "$PROFILE_PLIST" 2>/dev/null)"
    echo "  entitlements:"
    /usr/libexec/PlistBuddy -c "Print :Entitlements" "$PROFILE_PLIST" 2>/dev/null | sed 's/^/    /'

    # --- put it where Xcode looks -----------------------------------------

    mkdir -p "$PROFILE_DIR"

    # The profile it replaces is moved aside, not deleted: two profiles for the
    # same app id would leave Xcode to guess which one to sign with, and the old
    # one — the audio profile — would be the wrong guess. The file name loses its
    # extension, so Xcode does not see it any more.
    for existing in "$PROFILE_DIR"/*.mobileprovision; do
        [ -f "$existing" ] || continue
        [ "$existing" = "$PROFILE" ] && continue
        existing_plist="$(mktemp -t carplay-existing)"
        if decode "$existing" "$existing_plist" \
            && [ "$(app_id_of "$existing_plist")" = "$TEAM_ID.$APP_ID" ]; then
            mv "$existing" "$existing.superseded"
            echo "  moved the old profile for this app id aside: $(basename "$existing").superseded"
        fi
        rm -f "$existing_plist"
    done

    if [ "$(dirname "$PROFILE")" != "$PROFILE_DIR" ]; then
        cp "$PROFILE" "$PROFILE_DIR/$(basename "$PROFILE")"
        echo "  installed into $PROFILE_DIR"
    fi
fi

# --- the phone --------------------------------------------------------------

UDID="${2:-$(xcrun devicectl list devices --json-output - 2>/dev/null | python3 -c '
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
')}"
if [ -z "$UDID" ]; then
    echo "ERROR: no connected iPhone. Plug it in and trust this Mac."
    exit 1
fi

# --- build ------------------------------------------------------------------

echo
echo "Building the video build for $UDID ..."
xcodebuild -project CarTV.xcodeproj -scheme CarTV -configuration Debug \
    -destination "id=$UDID" -derivedDataPath build \
    CARPLAY_CATEGORY=video \
    -allowProvisioningUpdates \
    build || exit 1

APP="build/Build/Products/Debug-iphoneos/CarTV.app"

echo
echo "Entitlements the app was signed with:"
codesign -d --entitlements :- "$APP" 2>&1 | grep -E 'carplay|application-identifier' | sed 's/^/  /'

if ! codesign -d --entitlements :- "$APP" 2>&1 | grep -q 'carplay-video'; then
    echo
    echo "ERROR: the app was not signed with the CarPlay video entitlement."
    echo "       Xcode picked the wrong profile — check the one that is installed."
    exit 1
fi

echo
echo "Installing on the phone ..."
xcrun devicectl device install app --device "$UDID" "$APP" || exit 1

echo
echo "Done. Open CarPlay and pick DrivePlay — the channel rows now ask for video."
