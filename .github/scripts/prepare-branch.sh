#!/bin/sh
# Create (or update with FORCE=true) the version branch for one upstream tag.
#
# Xray-core-style model: branch name == upstream tag (e.g. 2.0.2.7), created
# from the upstream tag commit with CORS patches applied as two commits:
#   1. Functional: core CORS image proxy implementation
#   2. Non-functional: package rename + localization updates
#
# Usage: prepare-branch.sh <tag>
# Env: OWNER, MAIN_REPO, UPSTREAM_REPO, REPO_TOKEN, FORCE, RUNNER_TEMP
set -eu

TAG="${1:?usage: prepare-branch.sh <tag>}"
OWNER="${OWNER:-zero-custom}"
MAIN_REPO="${MAIN_REPO:-$OWNER/Ehviewer_CN_SXJ}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/xiaojieonly/Ehviewer_CN_SXJ.git}"
FORCE="${FORCE:-false}"

if ! printf '%s' "$TAG" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "invalid tag: $TAG" >&2
    exit 1
fi

WORK="${RUNNER_TEMP:-/tmp}/ehviewer-$TAG"
PATCH_DIR="${GITHUB_WORKSPACE:-$(pwd)}/patches"
rm -rf "$WORK"
git worktree prune >/dev/null 2>&1 || true

git remote add upstream "$UPSTREAM_REPO" 2>/dev/null || true
git fetch upstream "refs/tags/$TAG"

if git ls-remote --exit-code --heads origin "refs/heads/$TAG" >/dev/null 2>&1; then
    if [ "$FORCE" != "true" ]; then
        echo "branch already exists: $TAG (skip; use force=true to rebuild)"
        exit 0
    fi
    echo "updating existing branch: $TAG"
fi

git worktree add --detach "$WORK" FETCH_HEAD
cd "$WORK"

# Commit 1: Functional CORS image proxy patch
PATCH1="$PATCH_DIR/ehviewer-cors-functional.patch"
if git apply --check "$PATCH1"; then
    git apply "$PATCH1"
elif git apply --reverse --check "$PATCH1"; then
    echo "functional patch already applied on $TAG"
else
    echo "functional patch failed to apply on $TAG" >&2
    exit 2
fi

git config user.email "github-actions@github.com"
git config user.name "GitHub Actions"
git add -A
git commit -m "CORS image proxy: core implementation with relay, fallback, and retry logic ($TAG)"

# Commit 2: Non-functional rename + localization patch
PATCH2="$PATCH_DIR/ehviewer-cors-nonfunctional.patch"
if git apply --check "$PATCH2"; then
    git apply "$PATCH2"
elif git apply --reverse --check "$PATCH2"; then
    echo "non-functional patch already applied on $TAG"
else
    echo "non-functional patch failed to apply on $TAG" >&2
    exit 2
fi

git add -A
git commit -m "rename: package com.zero.ehviewer and localize app name for zero-custom fork"
git push --force origin "HEAD:refs/heads/$TAG"
echo "branch ready: $TAG (2 commits, worktree: $WORK)"
