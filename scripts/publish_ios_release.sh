#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/ios/build"
ENV_FILE="$ROOT_DIR/.env"
IPA_PATH=""
NOTES="${SONA_RELEASE_NOTES:-}"
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage:
  ./scripts/publish_ios_release.sh [IPA_PATH] [--notes TEXT] [--dry-run]

With no IPA_PATH, publishes the newest Sona-unsigned-*.ipa in ios/build.
Server URL and administrator credentials are read from the ignored .env file:
  SONA_PUBLIC_URL
  SONA_ADMIN_USERNAME
  SONA_ADMIN_PASSWORD
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --notes)
            [[ $# -ge 2 ]] || { echo "--notes requires a value" >&2; exit 2; }
            NOTES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -* )
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            [[ -z "$IPA_PATH" ]] || { echo "Only one IPA path is allowed" >&2; exit 2; }
            IPA_PATH="$1"
            shift
            ;;
    esac
done

if [[ -z "$IPA_PATH" ]]; then
    for candidate in "$BUILD_DIR"/Sona-unsigned-*.ipa; do
        [[ -f "$candidate" ]] || continue
        if [[ -z "$IPA_PATH" || "$candidate" -nt "$IPA_PATH" ]]; then
            IPA_PATH="$candidate"
        fi
    done
elif [[ "$IPA_PATH" != /* ]]; then
    IPA_PATH="$ROOT_DIR/$IPA_PATH"
fi

if [[ -z "$IPA_PATH" || ! -f "$IPA_PATH" ]]; then
    echo "No IPA found. Run ./ios/build_unsigned_ipa.sh first." >&2
    exit 1
fi

for command in unzip python3; do
    command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done
if [[ ! -x /usr/libexec/PlistBuddy ]]; then
    echo "PlistBuddy is required; run this script on macOS." >&2
    exit 1
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sona-release.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

INFO_ENTRY="$(unzip -Z1 "$IPA_PATH" | awk '/^Payload\/[^\/]+\.app\/Info\.plist$/ { print; exit }')"
if [[ -z "$INFO_ENTRY" ]]; then
    echo "IPA does not contain Payload/*.app/Info.plist" >&2
    exit 1
fi
unzip -p "$IPA_PATH" "$INFO_ENTRY" > "$TEMP_DIR/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TEMP_DIR/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TEMP_DIR/Info.plist")"

echo "IPA: $IPA_PATH"
echo "Version: $VERSION ($BUILD)"

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run complete; nothing was uploaded."
    exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing $ENV_FILE" >&2
    exit 1
fi

read_env_value() {
    local key="$1"
    local current="${!key:-}"
    local line value
    if [[ -n "$current" ]]; then
        return 0
    fi
    line="$(awk -v key="$key" 'index($0, key "=") == 1 { value = substr($0, length(key) + 2) } END { print value }' "$ENV_FILE")"
    value="${line%$'\r'}"
    if [[ ${#value} -ge 2 ]]; then
        if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]] \
            || [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi
    printf -v "$key" '%s' "$value"
}

read_env_value SONA_PUBLIC_URL
read_env_value SONA_ADMIN_USERNAME
read_env_value SONA_ADMIN_PASSWORD

SERVER_URL="${SONA_PUBLIC_URL:-}"
ADMIN_USERNAME="${SONA_ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${SONA_ADMIN_PASSWORD:-}"
SERVER_URL="${SERVER_URL%/}"

[[ -n "$SERVER_URL" ]] || { echo "SONA_PUBLIC_URL is missing from .env" >&2; exit 1; }
[[ -n "$ADMIN_PASSWORD" ]] || { echo "SONA_ADMIN_PASSWORD is missing from .env" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

if [[ -t 0 && -z "$NOTES" ]]; then
    read -r -p "Release notes (optional): " NOTES
fi

printf '%s\n%s\n' "$ADMIN_USERNAME" "$ADMIN_PASSWORD" \
    | python3 -c 'import json, sys; print(json.dumps({"username": sys.stdin.readline().rstrip("\n"), "password": sys.stdin.readline().rstrip("\n")}))' \
    > "$TEMP_DIR/login.json"

echo "Publishing to: $SERVER_URL"
curl --fail --silent --show-error \
    --connect-timeout 10 \
    --cookie-jar "$TEMP_DIR/cookies" \
    --header 'Content-Type: application/json' \
    --data-binary "@$TEMP_DIR/login.json" \
    "$SERVER_URL/api/v1/auth/login" >/dev/null

curl --fail --silent --show-error \
    --connect-timeout 10 \
    --cookie "$TEMP_DIR/cookies" \
    --form-string "version=$VERSION" \
    --form-string "build=$BUILD" \
    --form-string "notes=$NOTES" \
    --form "file=@$IPA_PATH;type=application/octet-stream" \
    "$SERVER_URL/api/v1/app/releases"
echo

echo "Published release:"
curl --fail --silent --show-error \
    --connect-timeout 10 \
    --cookie "$TEMP_DIR/cookies" \
    "$SERVER_URL/api/v1/app/releases/latest"
echo
