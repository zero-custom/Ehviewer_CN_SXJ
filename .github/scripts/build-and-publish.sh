#!/bin/sh
# Build a release APK from a prepared version branch, apply the fork-only debug
# overlay, sign with the fixed custom keystore, publish an independent pN
# release in the main repo, and update the `update` branch feed.
#
# Usage: build-and-publish.sh <tag>
# Env: OWNER, MAIN_REPO, REPO_TOKEN, SIGNING_* secrets, FORCE, RUNNER_TEMP,
#      GITHUB_WORKSPACE
set -eu

TAG="${1:?usage: build-and-publish.sh <tag>}"
OWNER="${OWNER:-zero-custom}"
MAIN_REPO="${MAIN_REPO:-$OWNER/Ehviewer_CN_SXJ}"
TOKEN="${REPO_TOKEN:?REPO_TOKEN is required}"
FORCE="${FORCE:-false}"
WORK="${RUNNER_TEMP:-/tmp}/ehviewer-$TAG"
PATCH_DIR="${GITHUB_WORKSPACE:-$(pwd)}/patches"

: "${SIGNING_KEYSTORE_BASE64:?SIGNING_KEYSTORE_BASE64 is required}"
: "${SIGNING_STORE_PASSWORD:?SIGNING_STORE_PASSWORD is required}"
: "${SIGNING_KEY_ALIAS:?SIGNING_KEY_ALIAS is required}"
: "${SIGNING_KEY_PASSWORD:?SIGNING_KEY_PASSWORD is required}"

if [ ! -d "$WORK" ]; then
    echo "prepared branch worktree not found: $WORK" >&2
    exit 1
fi
cd "$WORK"

echo "==> apply fork debug overlay"
DEBUG_PATCH="$PATCH_DIR/ehviewer-cors-debug.patch"
if [ ! -f "$DEBUG_PATCH" ]; then
    echo "debug patch not found: $DEBUG_PATCH" >&2
    exit 1
fi
if git apply --check "$DEBUG_PATCH"; then
    git apply "$DEBUG_PATCH"
elif git apply --reverse --check "$DEBUG_PATCH"; then
    echo "debug overlay already applied"
else
    echo "debug overlay failed to apply on $TAG" >&2
    exit 2
fi

echo "==> compute pN revision"
RELEASES="$(gh release list --repo "$MAIN_REPO" --limit 500 --json tagName \
    -q '.[].tagName' 2>/dev/null || true)"
LAST_N="$(printf '%s\n' "$RELEASES" \
    | grep -E "^${TAG}-cors-p[0-9]+$" \
    | sed -E 's/.*-p([0-9]+)$/\1/' \
    | sort -n | tail -n 1 || true)"
N=$(( ${LAST_N:-0} + 1 ))

OLDIFS=$IFS
IFS=.
set -- $TAG
IFS=$OLDIFS
A="${1:-}"
B="${2:-}"
C="${3:-}"
D="${4:-}"
for part in "$A" "$B" "$C" "$D"; do
    case "$part" in
        ''|*[!0-9]*) echo "invalid tag segment: $TAG" >&2; exit 1 ;;
    esac
    if [ "$part" -gt 99 ]; then
        echo "tag segment exceeds 99: $TAG" >&2
        exit 1
    fi
done
TAG_CODE=$((A * 1000000 + B * 10000 + C * 100 + D))
VERSION_CODE=$((TAG_CODE * 100 + N))
if [ "$VERSION_CODE" -gt 2147483647 ]; then
    echo "versionCode exceeds int range: $VERSION_CODE" >&2
    exit 1
fi
VERSION_NAME="${TAG}-p${N}"
RELEASE_TAG="${TAG}-cors-p${N}"
ASSET_NAME="EhViewer-${TAG}-p${N}-cors.apk"

echo "==> build release APK ($VERSION_NAME / $VERSION_CODE)"
chmod +x gradlew
# Force both version fields so the APK, feed, and update check agree even when
# the upstream tag carries a stale versionName/versionCode.
sed -i -E "s/versionName[[:space:]]+\"[^\"]*\"/versionName \"$VERSION_NAME\"/" app/build.gradle
sed -i -E "s/versionCode[[:space:]]+[0-9]+/versionCode $VERSION_CODE/" app/build.gradle
./gradlew --no-daemon :app:assembleAppReleaseRelease

UNSIGNED="$(find app/build/outputs/apk/appRelease/release -name '*.apk' -type f | head -n 1 || true)"
if [ -z "$UNSIGNED" ]; then
    echo "release APK not found" >&2
    exit 1
fi
case "$UNSIGNED" in
    *debug*) echo "refusing to publish a debug APK: $UNSIGNED" >&2; exit 1 ;;
esac

BUILD_TOOLS_DIR="$(ls -d "${ANDROID_HOME:-$ANDROID_SDK_ROOT}"/build-tools/* 2>/dev/null | sort -V | tail -n 1 || true)"
if [ -z "$BUILD_TOOLS_DIR" ]; then
    echo "Android build-tools not found" >&2
    exit 1
fi
ZIPALIGN="$BUILD_TOOLS_DIR/zipalign"
APKSIGNER="$BUILD_TOOLS_DIR/apksigner"

printf '%s' "$SIGNING_KEYSTORE_BASE64" | base64 -d > "$WORK/release.keystore"

echo "==> zipalign + sign"
"$ZIPALIGN" -p -f 4 "$UNSIGNED" "$WORK/aligned.apk"
OUT="$WORK/$ASSET_NAME"
"$APKSIGNER" sign \
    --ks "$WORK/release.keystore" \
    --ks-key-alias "$SIGNING_KEY_ALIAS" \
    --ks-pass "env:SIGNING_STORE_PASSWORD" \
    --key-pass "env:SIGNING_KEY_PASSWORD" \
    --out "$OUT" "$WORK/aligned.apk"
"$APKSIGNER" verify --print-certs "$OUT"

READ_VERSION_CODE="$(grep -E '^[[:space:]]*versionCode[[:space:]]+' app/build.gradle | head -n 1 | awk '{print $2}')"
READ_VERSION_NAME="$(grep -E '^[[:space:]]*versionName[[:space:]]+' app/build.gradle | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [ "$READ_VERSION_CODE" != "$VERSION_CODE" ] || [ "$READ_VERSION_NAME" != "$VERSION_NAME" ]; then
    echo "version mismatch: build.gradle has $READ_VERSION_NAME/$READ_VERSION_CODE" >&2
    exit 1
fi

NOTES="$WORK/notes.md"
cat > "$NOTES" <<EOF
## EhViewer CORS $TAG p$N

- Upstream: \`xiaojieonly/Ehviewer_CN_SXJ@$TAG\`
- Version: \`$VERSION_NAME\` (versionCode \`$VERSION_CODE\`)
- Branch: \`$TAG\` (upstream tag + functional/non-functional commits)
- Patches: \`patches/ehviewer-cors-functional.patch\` + \`patches/ehviewer-cors-nonfunctional.patch\`
- Fork overlay: \`patches/ehviewer-cors-debug.patch\` (online log API, compareVersion)
- Package: \`com.zero.ehviewer\` (installs alongside official EhViewer)
- Signing: fixed custom keystore, not the official key
- APK: \`$ASSET_NAME\`

CORS 图片加速：图片优先走自定义 CORS 中转，失败自动回退原图。
在线日志 API（仅 fork）：开启后访问 \`http://<设备IP>:18765/logs\`。
EOF

APK_URL="https://github.com/$MAIN_REPO/releases/download/$RELEASE_TAG/$ASSET_NAME"

echo "==> publish release $RELEASE_TAG"
if gh release view "$RELEASE_TAG" --repo "$MAIN_REPO" >/dev/null 2>&1; then
    echo "release already exists: $RELEASE_TAG"
    gh release upload "$RELEASE_TAG" "$OUT" --repo "$MAIN_REPO" --clobber
else
    gh release create "$RELEASE_TAG" "$OUT" --repo "$MAIN_REPO" \
        --target "$TAG" --title "EhViewer CORS $TAG p$N" --notes-file "$NOTES"
fi

echo "==> update $MAIN_REPO update branch"
UPDATE_DIR="$WORK/update-feed"
if git clone --depth 1 --branch update \
        "https://x-access-token:${TOKEN}@github.com/${MAIN_REPO}.git" "$UPDATE_DIR" 2>/dev/null; then
    :
else
    rm -rf "$UPDATE_DIR"
    git clone --depth 1 "https://x-access-token:${TOKEN}@github.com/${MAIN_REPO}.git" "$UPDATE_DIR"
    cd "$UPDATE_DIR"
    git checkout --orphan update
    git rm -rf . >/dev/null 2>&1 || true
fi
cd "$UPDATE_DIR"
git config user.email "github-actions@github.com"
git config user.name "GitHub Actions"
mkdir -p feedauthor
python3 - "$UPDATE_DIR/feedauthor/update.json" "$VERSION_NAME" "$VERSION_CODE" "$APK_URL" "$TAG" <<'PY'
import json
import sys

path, version, version_code, apk_url, tag = sys.argv[1:6]
data = {
    "version": version,
    "versionCode": int(version_code),
    "mustUpdate": False,
    "updateContent": {
        "fileDownloadUrl": apk_url,
        "title": "EhViewer CORS " + version,
        "content": [
            "CORS 图片加速",
            "失败自动回退原图",
            "包名 com.zero.ehviewer",
            "在线日志 API（fork）",
        ],
    },
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
git add feedauthor/update.json
if ! git diff --cached --quiet; then
    git commit -m "update feed for $RELEASE_TAG"
fi
git push origin update

echo "published: $MAIN_REPO $RELEASE_TAG ($VERSION_NAME) -> $APK_URL"
