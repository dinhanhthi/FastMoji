#!/usr/bin/env bash
#
# bump-version.sh — Bump FastMoji's version for a release.
#
# Edits the two version settings in FastMoji.xcodeproj/project.pbxproj (project-level
# Debug + Release, so each appears twice and both copies must stay identical):
#   MARKETING_VERSION       -> CFBundleShortVersionString (user-facing)
#   CURRENT_PROJECT_VERSION -> CFBundleVersion (build number, Sparkle compare key)
#
# The build number ALWAYS increments by 1. Sparkle ships an update only when
# CFBundleVersion strictly increases — bump it every single release.
#
# Usage:
#   scripts/bump-version.sh 1.1.0     # set marketing version 1.1.0, build +1
#   scripts/bump-version.sh           # keep marketing version, build +1 only
#   PBXPROJ=/tmp/project.pbxproj scripts/bump-version.sh 1.0.1   # edit another file (tests)
#
# Review the diff and commit the bump yourself.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PBXPROJ="${PBXPROJ:-$REPO_ROOT/FastMoji.xcodeproj/project.pbxproj}"
NEW_MARKETING="${1:-}"

[[ -f "$PBXPROJ" ]] || { echo "error: $PBXPROJ not found" >&2; exit 1; }

if [[ -n "$NEW_MARKETING" && ! "$NEW_MARKETING" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: marketing version must look like 1.2.3 (got \"$NEW_MARKETING\")" >&2
  exit 1
fi

BUILDS="$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/p' "$PBXPROJ" | sort -u)"
[[ -n "$BUILDS" ]] || { echo "error: no CURRENT_PROJECT_VERSION found in $PBXPROJ" >&2; exit 1; }
if [[ "$(printf '%s\n' "$BUILDS" | wc -l | tr -d ' ')" != "1" ]]; then
  echo "error: CURRENT_PROJECT_VERSION differs between configurations in $PBXPROJ:" >&2
  printf '  %s\n' $BUILDS >&2
  exit 1
fi
CURRENT_BUILD="$BUILDS"
NEXT_BUILD=$((CURRENT_BUILD + 1))

perl -i -pe "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\${1}${NEXT_BUILD};/" "$PBXPROJ"
if [[ -n "$NEW_MARKETING" ]]; then
  perl -i -pe "s/(MARKETING_VERSION = )[0-9.]+;/\${1}${NEW_MARKETING};/" "$PBXPROJ"
fi

echo "==> Build number (CFBundleVersion):  ${CURRENT_BUILD} -> ${NEXT_BUILD}"
if [[ -n "$NEW_MARKETING" ]]; then
  echo "==> Marketing version:               set to ${NEW_MARKETING}"
else
  echo "==> Marketing version:               unchanged"
fi
grep -nE 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' "$PBXPROJ"
