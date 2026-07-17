#!/usr/bin/env bash

# Build a reproducible, unsigned device IPA for local sideloading.
#
# The resulting archive is intentionally not installable until it is signed
# with the user's own certificate/provisioning profile.  The app bundle still
# contains the complete Info.plist and compiled AppIcon, which most signing
# tools use to populate their signing form.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  ./ios/build_unsigned_ipa.sh [output.ipa]

Builds an arm64 Release IPA without code signing or a provisioning profile.
When output.ipa is omitted, the package is written to ios/build with its
incremented patch version in the file name (for example, Sona-unsigned-0.5.1.ipa).
Press Enter at the version prompt to use the incremented patch version, or enter
a larger version such as 0.6.0. SONA_IOS_VERSION provides the same override.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if (( $# > 1 )); then
    usage >&2
    exit 2
fi

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$IOS_DIR/Sona.xcodeproj"
PROJECT_FILE="$PROJECT/project.pbxproj"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sona-unsigned-ipa.XXXXXX")"
DERIVED_DATA="$WORK_DIR/DerivedData"
OUTPUT="${1:-}"

trap 'rm -rf "$WORK_DIR"' EXIT

if [[ -n "$OUTPUT" && "$OUTPUT" != /* ]]; then
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

CURRENT_VERSION="$(awk -F ' = ' '
    /MARKETING_VERSION =/ {
        value = $2
        sub(/;$/, "", value)
        print value
        exit
    }
' "$PROJECT_FILE")"
if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Unsupported MARKETING_VERSION: $CURRENT_VERSION" >&2
    exit 1
fi
DEFAULT_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
NEXT_VERSION="${SONA_IOS_VERSION:-}"
if [[ -z "$NEXT_VERSION" && -t 0 ]]; then
    read -r -p "Version [$DEFAULT_VERSION]: " NEXT_VERSION
fi
NEXT_VERSION="${NEXT_VERSION:-$DEFAULT_VERSION}"
if [[ ! "$NEXT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version: $NEXT_VERSION (expected x.y.z)" >&2
    exit 1
fi

version_is_greater() {
    local current_major current_minor current_patch
    local next_major next_minor next_patch
    IFS=. read -r current_major current_minor current_patch <<< "$CURRENT_VERSION"
    IFS=. read -r next_major next_minor next_patch <<< "$NEXT_VERSION"
    if (( 10#$next_major != 10#$current_major )); then
        (( 10#$next_major > 10#$current_major ))
        return
    fi
    if (( 10#$next_minor != 10#$current_minor )); then
        (( 10#$next_minor > 10#$current_minor ))
        return
    fi
    (( 10#$next_patch > 10#$current_patch ))
}

if ! version_is_greater; then
    echo "Version $NEXT_VERSION must be greater than $CURRENT_VERSION" >&2
    exit 1
fi

echo "[1/4] 正在构建未签名 Sona.app ${NEXT_VERSION}（iOS Release）…"
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
    MARKETING_VERSION="$NEXT_VERSION" \
    build > "$WORK_DIR/xcodebuild.log" 2>&1 &
BUILD_PID=$!
BUILD_SECONDS=0
while kill -0 "$BUILD_PID" 2>/dev/null; do
    sleep 10
    BUILD_SECONDS=$((BUILD_SECONDS + 10))
    if kill -0 "$BUILD_PID" 2>/dev/null; then
        echo "[1/4] 仍在编译（${BUILD_SECONDS} 秒）…"
    fi
done
if ! wait "$BUILD_PID"; then
    cat "$WORK_DIR/xcodebuild.log" >&2
    exit 1
fi
echo "[1/4] 构建完成。"

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

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
if [[ "$VERSION" != "$NEXT_VERSION" ]]; then
    echo "Built version $VERSION does not match expected version $NEXT_VERSION" >&2
    exit 1
fi
if [[ -z "$OUTPUT" ]]; then
    OUTPUT="$IOS_DIR/build/Sona-unsigned-$VERSION.ipa"
fi
if [[ -e "$OUTPUT" ]]; then
    echo "Output already exists; choose another path: $OUTPUT" >&2
    exit 1
fi
mkdir -p "$(dirname "$OUTPUT")"

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
echo "[2/4] 正在准备 IPA 内容…"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/Sona.app"

echo "[3/4] 正在压缩 IPA…"
(cd "$STAGE" && zip -qry "$OUTPUT" Payload)

echo "[4/4] 正在校验 IPA…"
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

OLD_VERSION="$CURRENT_VERSION" NEW_VERSION="$NEXT_VERSION" perl -0pi -e '
    s/MARKETING_VERSION = \Q$ENV{OLD_VERSION}\E;/MARKETING_VERSION = $ENV{NEW_VERSION};/g
' "$PROJECT_FILE"
if grep -F "MARKETING_VERSION = $CURRENT_VERSION;" "$PROJECT_FILE" >/dev/null; then
    echo "Failed to persist MARKETING_VERSION $NEXT_VERSION" >&2
    exit 1
fi

echo "Unsigned IPA: $OUTPUT"
echo "Bundle: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
echo "Version: $VERSION ($BUILD)"
echo "Architecture: $ARCHS"
echo "The IPA is intentionally unsigned; sign it with your own certificate/profile before installing."
