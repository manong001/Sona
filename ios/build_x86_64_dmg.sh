#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ROOT="$SCRIPT_DIR/build/macos-x86_64"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
PROJECT_FILE="$SCRIPT_DIR/Sona.xcodeproj/project.pbxproj"
VERSION="$(awk -F ' = ' '/MARKETING_VERSION =/ { sub(/;$/, "", $2); print $2; exit }' "$PROJECT_FILE")"
BUILD_NUMBER="$(awk -F ' = ' '/CURRENT_PROJECT_VERSION =/ { sub(/;$/, "", $2); print $2; exit }' "$PROJECT_FILE")"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK_DIR="$BUILD_ROOT/package-$STAMP"
STAGING_DIR="$WORK_DIR/Sona"
MOUNT_DIR="$WORK_DIR/mount"
OUTPUT_PATH="${1:-$BUILD_ROOT/Sona-$VERSION-build$BUILD_NUMBER-x86_64-$STAMP.dmg}"
MOUNTED=false

cleanup() {
    if [[ "$MOUNTED" == true ]]; then
        echo "正在卸载临时验证映像…"
        hdiutil detach "$MOUNT_DIR" -quiet || true
    fi
}

trap cleanup EXIT INT TERM

retry_hdiutil() {
    local action="$1"
    shift
    local attempt
    for attempt in {1..10}; do
        if "$@" >/dev/null 2>&1; then
            return 0
        fi
        if [[ "$attempt" -lt 10 ]]; then
            echo "$action 暂不可用，第 ${attempt}/10 次重试…"
            sleep 1
        fi
    done
    echo "$action 重试 10 次后仍未完成：" >&2
    "$@"
}

detachCreatedImage() {
    local device
    device="$(hdiutil info | awk -v image="$OUTPUT_PATH" '
        $1 == "image-path" { current = $3 }
        $1 ~ /^\/dev\/disk[0-9]+$/ && current == image { print $1; exit }
    ')"
    if [[ -n "$device" ]]; then
        echo "正在释放 DMG 创建时自动附加的映像…"
        hdiutil detach "$device" -quiet
    fi
}

for tool in xcodebuild hdiutil ditto codesign lipo; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "缺少打包工具：$tool" >&2
        exit 1
    fi
done

mkdir -p "$DERIVED_DATA" "$STAGING_DIR" "$MOUNT_DIR" "$(dirname "$OUTPUT_PATH")"

if [[ -e "$OUTPUT_PATH" ]]; then
    echo "输出文件已存在，请换一个路径：$OUTPUT_PATH" >&2
    exit 1
fi

echo "[1/5] 正在构建 Intel x86_64 Mac Catalyst Release…"
xcodebuild \
    -project "$SCRIPT_DIR/Sona.xcodeproj" \
    -scheme Sona \
    -configuration Release \
    -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS=x86_64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH="$DERIVED_DATA/Build/Products/Release-maccatalyst/Sona.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "未找到 Catalyst 构建产物：$APP_PATH" >&2
    exit 1
fi

echo "[2/5] 正在准备应用包…"
ditto "$APP_PATH" "$STAGING_DIR/Sona.app"
ln -s /Applications "$STAGING_DIR/Applications"

codesign --force --deep --sign - "$STAGING_DIR/Sona.app"
codesign --verify --deep --strict "$STAGING_DIR/Sona.app"

echo "[3/5] 正在创建 DMG（压缩时间取决于应用大小）…"
hdiutil create \
    -volname "Sona" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$OUTPUT_PATH"

detachCreatedImage
echo "[4/5] 正在校验 DMG…"
retry_hdiutil "DMG 校验" hdiutil verify "$OUTPUT_PATH"
echo "[5/5] 正在挂载并验证 Intel 架构…"
retry_hdiutil "DMG 挂载" hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$OUTPUT_PATH"
MOUNTED=true

MOUNTED_EXECUTABLE="$MOUNT_DIR/Sona.app/Contents/MacOS/Sona"
ARCHS_FOUND="$(lipo -archs "$MOUNTED_EXECUTABLE")"
if [[ "$ARCHS_FOUND" != "x86_64" ]]; then
    echo "架构验证失败，期望 x86_64，实际为：$ARCHS_FOUND" >&2
    exit 1
fi

codesign --verify --deep --strict "$MOUNT_DIR/Sona.app"
cleanup
MOUNTED=false

echo "DMG 已生成：$OUTPUT_PATH"
echo "可执行文件架构：$ARCHS_FOUND"
