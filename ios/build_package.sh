#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBLISH_SCRIPT="$ROOT_DIR/scripts/publish_ios_release.sh"
CHOICE="${1:-}"
OUTPUT_PATH="${2:-}"

if [[ -z "$CHOICE" ]]; then
    if [[ ! -t 0 ]]; then
        echo "非交互终端请显式指定选项：./ios/build_package.sh <1|2|3|4> [输出路径]" >&2
        exit 2
    fi
    echo "请选择打包格式："
    echo "  1. IPA，完成后自动上传（默认）"
    echo "  2. 仅打包 IPA"
    echo "  3. DMG（Apple Silicon arm64）"
    echo "  4. DMG（Intel x86_64）"
    read -r -p "请输入选项 [1]: " CHOICE || true
fi

CHOICE="${CHOICE:-1}"

if [[ -n "$OUTPUT_PATH" && "$OUTPUT_PATH" != /* ]]; then
    OUTPUT_PATH="$(pwd)/$OUTPUT_PATH"
fi

case "$CHOICE" in
    1|ipa-upload|IPA-UPLOAD)
        if [[ -n "$OUTPUT_PATH" ]]; then
            "$SCRIPT_DIR/build_unsigned_ipa.sh" "$OUTPUT_PATH"
            exec "$PUBLISH_SCRIPT" "$OUTPUT_PATH"
        fi
        "$SCRIPT_DIR/build_unsigned_ipa.sh"
        exec "$PUBLISH_SCRIPT"
        ;;
    2|ipa|IPA)
        if [[ -n "$OUTPUT_PATH" ]]; then
            exec "$SCRIPT_DIR/build_unsigned_ipa.sh" "$OUTPUT_PATH"
        fi
        exec "$SCRIPT_DIR/build_unsigned_ipa.sh"
        ;;
    3|dmg|DMG|arm64|ARM64)
        if [[ -n "$OUTPUT_PATH" ]]; then
            exec "$SCRIPT_DIR/build_arm64_dmg.sh" "$OUTPUT_PATH"
        fi
        exec "$SCRIPT_DIR/build_arm64_dmg.sh"
        ;;
    4|intel|INTEL|x86_64|X86_64)
        if [[ -n "$OUTPUT_PATH" ]]; then
            exec "$SCRIPT_DIR/build_x86_64_dmg.sh" "$OUTPUT_PATH"
        fi
        exec "$SCRIPT_DIR/build_x86_64_dmg.sh"
        ;;
    *)
        echo "无效选项：${CHOICE}（请输入 1、2、3 或 4）" >&2
        exit 2
        ;;
esac
