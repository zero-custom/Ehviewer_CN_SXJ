#!/bin/sh
# Detect upstream EhViewer tags that still need a release branch.
#
# Xray-core-style model: the branch is named exactly like the upstream tag
# (e.g. 2.0.2.7) in the main repo, and each build publishes an independent
# release tag <tag>-cors-p<n>.
#
# Environment:
#   OWNER          default zero-custom
#   MAIN_REPO      default $OWNER/Ehviewer_CN_SXJ
#   UPSTREAM_REPO  default https://github.com/xiaojieonly/Ehviewer_CN_SXJ.git
#   BASELINE_TAG   default 2.0.2.7
#   MANUAL_TAG     optional single tag
#   FORCE          true to ignore existing branches/releases
#   GH_TOKEN       token used by gh
#   GITHUB_OUTPUT  optional GitHub Actions output file
#
# Outputs: pending_tags (space separated), has_pending (true/false).
set -eu

OWNER="${OWNER:-zero-custom}"
MAIN_REPO="${MAIN_REPO:-$OWNER/Ehviewer_CN_SXJ}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/xiaojieonly/Ehviewer_CN_SXJ.git}"
BASELINE_TAG="${BASELINE_TAG:-2.0.2.7}"
MANUAL_TAG="${MANUAL_TAG:-}"
FORCE="${FORCE:-false}"

if ! printf '%s' "$BASELINE_TAG" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "invalid BASELINE_TAG: $BASELINE_TAG" >&2
    exit 1
fi

if [ -n "$MANUAL_TAG" ] \
        && ! printf '%s' "$MANUAL_TAG" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "invalid MANUAL_TAG: $MANUAL_TAG" >&2
    exit 1
fi

# Branches are the version markers. Prefer the local origin remote; fall back
# to the API if the checkout was pruned.
BRANCHES="$(git ls-remote --heads origin 2>/dev/null \
    | awk '{print $2}' \
    | sed -e 's|refs/heads/||' || true)"
if [ -z "$BRANCHES" ]; then
    BRANCHES="$(gh api "repos/$MAIN_REPO/branches?per_page=100" \
        --jq '.[].name' 2>/dev/null || true)"
fi

RELEASES="$(gh release list --repo "$MAIN_REPO" --limit 200 \
    --json tagName -q '.[].tagName' 2>/dev/null || true)"

branch_exists() {
    echo "$BRANCHES" | grep -qx "$1"
}

release_exists() {
    echo "$RELEASES" | grep -Eq "^$1-cors-p[0-9]+$"
}

echo "==> upstream tags from $UPSTREAM_REPO (baseline: $BASELINE_TAG)"
UPSTREAM_TAGS="$(git ls-remote --tags "$UPSTREAM_REPO" \
    | awk '{print $2}' \
    | sed -e 's|refs/tags/||' \
    | grep -v '\^{}$' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -u -V)"

if [ -n "$MANUAL_TAG" ]; then
    CANDIDATES="$MANUAL_TAG"
else
    CANDIDATES="$(printf '%s\n%s\n' "$UPSTREAM_TAGS" "$BASELINE_TAG" \
        | sort -u -V \
        | awk -v base="$BASELINE_TAG" 'f{print} $0==base{f=1}')"
fi

PENDING=""
for tag in $CANDIDATES; do
    if [ -z "$MANUAL_TAG" ] || [ "$FORCE" != "true" ]; then
        SMALLEST="$(printf '%s\n%s\n' "$BASELINE_TAG" "$tag" | sort -V | head -n 1)"
        if [ "$tag" = "$BASELINE_TAG" ] || [ "$SMALLEST" = "$tag" ]; then
            echo "skip (<= baseline): $tag"
            continue
        fi
    fi

    if [ "$FORCE" != "true" ]; then
        if branch_exists "$tag" && release_exists "$tag"; then
            echo "skip (already released): $tag"
            continue
        fi
    fi

    echo "pending: $tag"
    PENDING="$PENDING $tag"
done
PENDING="$(echo "$PENDING" | sed 's/^ //')"

if [ -z "$PENDING" ]; then
    HAS_PENDING="false"
else
    HAS_PENDING="true"
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "pending_tags=$PENDING"
        echo "has_pending=$HAS_PENDING"
    } >> "$GITHUB_OUTPUT"
else
    echo "pending_tags: $PENDING"
    echo "has_pending: $HAS_PENDING"
fi
