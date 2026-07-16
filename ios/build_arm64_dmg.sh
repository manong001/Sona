#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$SCRIPT_DIR/build/macos-arm64"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
PROJECT_FILE="$SCRIPT_DIR/Sona.xcodeproj/project.pbxproj"
VERSION="$(awk -F ' = ' '/MARKETING_VERSION =/ { sub(/;$/, "", $2); print $2; exit }' "$PROJECT_FILE")"
BUILD_NUMBER="$(awk -F ' = ' '/CURRENT_PROJECT_VERSION =/ { sub(/;$/, "", $2); print $2; exit }' "$PROJECT_FILE")"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK_DIR="$BUILD_ROOT/package-$STAMP"
STAGING_DIR="$WORK_DIR/Sona"
MOUNT_DIR="$WORK_DIR/mount"
OUTPUT_PATH="${1:-$BUILD_ROOT/Sona-$VERSION-build$BUILD_NUMBER-arm64-$STAMP.dmg}"

mkdir -p "$DERIVED_DATA" "$STAGING_DIR" "$MOUNT_DIR" "$(dirname "$OUTPUT_PATH")"

if [[ -e "$OUTPUT_PATH" ]]; then
    echo "输出文件已存在，请换一个路径：$OUTPUT_PATH" >&2
    exit 1
fi

xcodebuild \
    -project "$SCRIPT_DIR/Sona.xcodeproj" \
    -scheme Sona \
    -configuration Release \
    -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH="$DERIVED_DATA/Build/Products/Release-maccatalyst/Sona.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "未找到 Catalyst 构建产物：$APP_PATH" >&2
    exit 1
fi

ditto "$APP_PATH" "$STAGING_DIR/Sona.app"
ln -s /Applications "$STAGING_DIR/Applications"

codesign --force --deep --sign - "$STAGING_DIR/Sona.app"
codesign --verify --deep --strict "$STAGING_DIR/Sona.app"

hdiutil create \
    -volname "Sona" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$OUTPUT_PATH"

hdiutil verify "$OUTPUT_PATH"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$OUTPUT_PATH"

MOUNTED_EXECUTABLE="$MOUNT_DIR/Sona.app/Contents/MacOS/Sona"
ARCHS_FOUND="$(lipo -archs "$MOUNTED_EXECUTABLE")"
if [[ "$ARCHS_FOUND" != "arm64" ]]; then
    hdiutil detach "$MOUNT_DIR"
    echo "架构验证失败，实际为：$ARCHS_FOUND" >&2
    exit 1
fi

codesign --verify --deep --strict "$MOUNT_DIR/Sona.app"
hdiutil detach "$MOUNT_DIR"

echo "DMG 已生成：$OUTPUT_PATH"
echo "可执行文件架构：$ARCHS_FOUND"
