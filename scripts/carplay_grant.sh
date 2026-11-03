#!/bin/bash
# CarPlay entitlement helper for DrivePlay.
#
#   usage: scripts/carplay_grant.sh [check|grant] [udid]
#
# Apple grants the CarPlay capability, this script cannot. What it does:
#   check — says whether the local provisioning profile carries the entitlement
#           the app asks for (and which profile carries it)
#   grant — asks Xcode for a new profile that carries it. The phone has to be
#           connected and Apple has to have granted the capability already.
#
# The category is the build setting CARPLAY_CATEGORY ("audio" or "video"): it
# picks the entitlements file and has to match the capability on the app id.
#
# Nothing about the machine or the phone is hardcoded: the entitlements are
# read from CarTV/Resources/CarTV.<category>.entitlements, the profile is found
# in the local provisioning profile folders, the device is detected at run time.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

CARPLAY_CATEGORY="${CARPLAY_CATEGORY:-audio}"
ENTITLEMENTS_FILE="CarTV/Resources/CarTV.${CARPLAY_CATEGORY}.entitlements"
PROFILE_DIRS=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)

# The CarPlay keys the app asks for — read from the entitlements file, so the
# script follows the project instead of a copy of it.
carplay_keys() {
    /usr/libexec/PlistBuddy -c "Print" "$ENTITLEMENTS_FILE" 2>/dev/null \
        | grep -oE 'com\.apple\.developer\.carplay-[a-z-]+' | sort -u
}

# The local profiles of this app (the ones that name the bundle id).
#
# The path of the profile folder has a space in it ("Provisioning Profiles"),
# so the paths are never word-split and never piped into `grep -q`: a pipe
# would let `grep` exit before the profile was read, and `pipefail` would then
# call a perfectly good profile broken.
app_profiles() {
    local dir profile decoded
    for dir in "${PROFILE_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        for profile in "$dir"/*.mobileprovision "$dir"/*.provisionprofile; do
            [ -f "$profile" ] || continue
            decoded="$(security cms -D -i "$profile" 2>/dev/null)" || continue
            case "$decoded" in
                *com.rushabh.cartvv*) echo "$profile" ;;
            esac
        done
    done
}

# Does the decoded profile carry the key, set to true?
profile_has_key() {
    local plist="$1" key="$2" value
    value="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:$key" "$plist" 2>/dev/null)" || return 1
    [ "$value" = "true" ]
}

check() {
    local keys key profile plist matched
    echo "CarPlay category: $CARPLAY_CATEGORY ($ENTITLEMENTS_FILE)"
    keys="$(carplay_keys)"
    if [ -z "$keys" ]; then
        echo "ERROR: $ENTITLEMENTS_FILE asks for no CarPlay entitlement."
        return 1
    fi
    while IFS= read -r key; do
        matched=""
        while IFS= read -r profile; do
            [ -n "$profile" ] || continue
            plist="$(mktemp -t carplay-profile)"
            security cms -D -i "$profile" > "$plist" 2>/dev/null
            if profile_has_key "$plist" "$key"; then
                matched="$profile"
                rm -f "$plist"
                break
            fi
            rm -f "$plist"
        done <<< "$(app_profiles)"
        if [ -n "$matched" ]; then
            echo "OK       $key — carried by $(basename "$matched")"
        else
            echo "MISSING  $key — no local profile carries it (Apple has to grant it first)"
        fi
    done <<< "$keys"
}

grant() {
    local udid="${1:-}"
    if [ -z "$udid" ]; then
        udid="$(xcodebuild -project CarTV.xcodeproj -scheme CarTV -showdestinations 2>/dev/null \
            | grep -oE '\{ platform:iOS, id:[0-9A-Fa-f-]+' \
            | head -1 | sed 's/.*id://')"
    fi
    if [ -z "$udid" ]; then
        echo "ERROR: no connected iPhone found. Connect it (cable + trust this Mac)"
        echo "        or pass the udid: scripts/carplay_grant.sh grant <udid>"
        return 1
    fi

    echo "Building for $udid, asking Xcode for a profile that carries the entitlement ..."
    xcodebuild -project CarTV.xcodeproj -scheme CarTV -configuration Debug \
        -destination "id=$udid" -derivedDataPath build \
        CARPLAY_CATEGORY="$CARPLAY_CATEGORY" \
        -allowProvisioningUpdates build || return 1

    echo
    echo "Entitlements of the signed app:"
    codesign -d --entitlements :- "build/Build/Products/Debug-iphoneos/CarTV.app" 2>&1 \
        | grep -E 'carplay|application-identifier' || true
    echo
    check
}

case "${1:-check}" in
    check) check ;;
    grant) grant "${2:-}" ;;
    *)
        echo "usage: scripts/carplay_grant.sh [check|grant] [udid]"
        exit 1
        ;;
esac
