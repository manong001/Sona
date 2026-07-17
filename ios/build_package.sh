#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHOICE="${1:-}"
OUTPUT_PATH="${2:-}"

if [[ -z "$CHOICE" ]]; then
    if [[ ! -t 0 ]]; then
        echo "非交互终端请显式指定格式：./ios/build_package.sh dmg [输出路径]" >&2
        exit 2
    fi
    echo "请选择打包格式："
    echo "  1. IPA（默认）"
    echo "  2. DMG（Apple Silicon arm64）"
    read -r -p "请输入选项 [1]: " CHOICE || true
fi

CHOICE="${CHOICE:-1}"

case "$CHOICE" in
    1|ipa|IPA)
        if [[ -n "$OUTPUT_PATH" ]]; then
            exec "$SCRIPT_DIR/build_unsigned_ipa.sh" "$OUTPUT_PATH"
        fi
        exec "$SCRIPT_DIR/build_unsigned_ipa.sh"
        ;;
    2|dmg|DMG)
        if [[ -n "$OUTPUT_PATH" ]]; then
            exec "$SCRIPT_DIR/build_arm64_dmg.sh" "$OUTPUT_PATH"
        fi
        exec "$SCRIPT_DIR/build_arm64_dmg.sh"
        ;;
    *)
        echo "无效选项：${CHOICE}（请输入 1 或 2）" >&2
        exit 2
        ;;
esac
