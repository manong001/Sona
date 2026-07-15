#!/usr/bin/env bash

# Build a reproducible, unsigned device IPA for local sideloading.
#
# The resulting archive is intentionally not installable until it is signed
# with the user's own certificate/provisioning profile.  The app bundle still
# contains the complete Info.plist and compiled AppIcon, which most signing
# tools use to populate their signing form.

set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$IOS_DIR/Sona.xcodeproj"
WORK_DIR="$IOS_DIR/build/.unsigned-ipa"
DERIVED_DATA="$WORK_DIR/DerivedData"
DEFAULT_OUTPUT="$IOS_DIR/build/Sona-unsigned.ipa"
OUTPUT="${1:-$DEFAULT_OUTPUT}"

if [[ "$OUTPUT" != /* ]]; then
    OUTPUT="$(pwd)/$OUTPUT"
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild not found; run this script on macOS with Xcode installed." >&2
    exit 1
fi

if [[ ! -d "$PROJECT" ]]; then
    echo "Xcode project not found: $PROJECT" >&2
    exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$(dirname "$OUTPUT")"

echo "Building unsigned Sona.app (iOS Release)..."
xcodebuild \
    -project "$PROJECT" \
    -scheme Sona \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    build | tee "$WORK_DIR/xcodebuild.log"

APP="$DERIVED_DATA/Build/Products/Release-iphoneos/Sona.app"
EXECUTABLE="$APP/Sona"

if [[ ! -d "$APP" || ! -f "$EXECUTABLE" ]]; then
    echo "Build did not produce Sona.app: $APP" >&2
    exit 1
fi

PLIST="$APP/Info.plist"
if [[ ! -f "$PLIST" ]]; then
    echo "Missing app Info.plist: $PLIST" >&2
    exit 1
fi

require_plist_key() {
    local key="$1"
    if ! /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" >/dev/null 2>&1; then
        echo "Info.plist is missing required key: $key" >&2
        exit 1
    fi
}

for key in \
    CFBundleDisplayName \
    CFBundleExecutable \
    CFBundleIdentifier \
    CFBundleInfoDictionaryVersion \
    CFBundleName \
    CFBundlePackageType \
    CFBundleShortVersionString \
    CFBundleVersion \
    CFBundleIconName \
    MinimumOSVersion; do
    require_plist_key "$key"
done

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$PLIST")" != "APPL" ]]; then
    echo "Unexpected CFBundlePackageType in Info.plist" >&2
    exit 1
fi

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundleAlternateIcons:SpotifyIcon:CFBundleIconName' "$PLIST")" != "SpotifyIcon" ]]; then
    echo "Compiled app is missing the Spotify alternate icon registration" >&2
    exit 1
fi

ARCHS="$(lipo -archs "$EXECUTABLE")"
if [[ " $ARCHS " != *" arm64 "* ]]; then
    echo "Sona executable does not contain arm64: $ARCHS" >&2
    exit 1
fi

# A truly unsigned bundle must not have a signature or provisioning profile.
if [[ -e "$APP/_CodeSignature" || -e "$APP/embedded.mobileprovision" ]]; then
    echo "Build unexpectedly contains signing metadata" >&2
    exit 1
fi

# Asset compilation emits the device icon renditions from the 1024px source.
for icon in AppIcon60x60@2x.png AppIcon76x76@2x~ipad.png; do
    if [[ ! -s "$APP/$icon" ]]; then
        echo "Compiled AppIcon rendition is missing: $icon" >&2
        exit 1
    fi
done

STAGE="$WORK_DIR/stage"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/Sona.app"

rm -f "$OUTPUT"
(cd "$STAGE" && zip -qry "$OUTPUT" Payload)

if ! unzip -tqq "$OUTPUT"; then
    echo "Generated IPA failed ZIP validation: $OUTPUT" >&2
    exit 1
fi
# Do not use grep -q here: with pipefail, unzip can report SIGPIPE after grep
# exits early even though the archive is valid.
if ! unzip -l "$OUTPUT" | grep 'Payload/Sona.app/Info.plist' >/dev/null; then
    echo "Generated IPA does not contain Payload/Sona.app/Info.plist" >&2
    exit 1
fi

echo "Unsigned IPA: $OUTPUT"
echo "Bundle: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
echo "Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST") $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
echo "Architecture: $ARCHS"
echo "The IPA is intentionally unsigned; sign it with your own certificate/profile before installing."
