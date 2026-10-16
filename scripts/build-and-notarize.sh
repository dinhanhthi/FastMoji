#!/usr/bin/env bash
#
# build-and-notarize.sh — Build → sign → notarize → staple a release locally (docs/RELEASING.md §1).
#
# Releases are built locally only (there is no CI release workflow).
#
# Produces, under release/export/:
#   - FastMoji-<version>.zip   notarized + stapled  → Sparkle auto-update asset
#   - FastMoji-<version>.dmg   notarized + stapled  → manual-download asset
# Then hand the .zip to scripts/publish-release.sh to tag + create the GitHub Release
# (scripts/ship.sh runs the whole chain).
#
# Prereqs (one-time — see docs/RELEASING.md §0):
#   - "Developer ID Application" cert in the login Keychain
#   - notarytool credential profile (default "fastmoji-notary")
#   - Sparkle EdDSA public key pasted into SUPublicEDKey (FastMoji/Info.plist)
#
# Notarization talks to Apple, so this needs network — "local" means your machine, not offline.
#
# Usage:
#   scripts/build-and-notarize.sh
#   FASTMOJI_NOTARY_PROFILE=my-profile scripts/build-and-notarize.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PROJECT="FastMoji.xcodeproj"
INFO_PLIST="FastMoji/Info.plist"
ARCHIVE="release/FastMoji.xcarchive"
EXPORT_DIR="release/export"
APP="$EXPORT_DIR/FastMoji.app"
MIN_MACOS="14.0"   # FastMoji's hard minimum (project.pbxproj) — guarded below
PROFILE="${FASTMOJI_NOTARY_PROFILE:-fastmoji-notary}"

# Submit to Apple and FAIL the script on anything other than "Accepted". notarytool exits 0
# even when the status is Invalid, so without this an Invalid result sails on into stapler and
# surfaces as a confusing "Error 65" instead of a clear stop. On failure, print the log command.
notarize() {  # $1 = file to submit (zip or dmg)
  local out sid
  if ! out="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)"; then
    echo "$out" >&2
    echo "error: notarytool submit failed" >&2
    exit 1
  fi
  echo "$out"
  grep -q "status: Accepted" <<<"$out" && return 0
  sid="$(grep -m1 '  id:' <<<"$out" | awk '{print $2}')"
  echo "error: notarization not Accepted for $1 — pull the log to see which binary failed:" >&2
  echo "       xcrun notarytool log $sid --keychain-profile $PROFILE" >&2
  exit 1
}

# --- 0. Tools & prereqs (all before the slow archive) -----------------------
command -v xcodebuild >/dev/null || { echo "error: xcodebuild not found" >&2; exit 1; }
[[ -d "$PROJECT" && -f "$INFO_PLIST" ]] \
  || { echo "error: $PROJECT / $INFO_PLIST not found — run from the FastMoji repo" >&2; exit 1; }

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || { echo "error: no 'Developer ID Application' identity in the keychain." >&2
       echo "       Create it in Xcode › Settings › Accounts › Manage Certificates (docs/RELEASING.md §0)." >&2
       exit 1; }

# Sparkle refuses unsigned updates: an empty SUPublicEDKey would ship an app that can never
# verify (and so never install) an update.
ED_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" 2>/dev/null | tr -d '[:space:]' || true)"
[[ -n "$ED_KEY" ]] \
  || { echo "error: SUPublicEDKey is empty in $INFO_PLIST — Sparkle could never verify an update." >&2
       echo "       Run Sparkle's generate_keys --account FastMoji and paste the public key (docs/RELEASING.md §0)." >&2
       exit 1; }

FEED_URL="$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST" 2>/dev/null | tr -d '[:space:]' || true)"
[[ "$FEED_URL" == https://* ]] \
  || { echo "error: SUFeedURL in $INFO_PLIST is '${FEED_URL:-unset}', expected an https:// URL." >&2
       echo "       Point it at the GitHub Pages appcast (docs/RELEASING.md §0)." >&2
       exit 1; }

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || { echo "error: notarytool credential profile '$PROFILE' is missing or invalid." >&2
       echo "       Create it: xcrun notarytool store-credentials fastmoji-notary --apple-id <id> --team-id 86H6CNLN4C" >&2
       echo "       or reuse a profile of the same team: FASTMOJI_NOTARY_PROFILE=<profile-name> scripts/build-and-notarize.sh" >&2
       echo "       (docs/RELEASING.md §0)" >&2
       exit 1; }

# --- 1. Guard the Release settings ------------------------------------------
# Check, don't override: a command-line override would apply to every target, including the
# SPM packages.
APP_SETTINGS="$(xcodebuild -project "$PROJECT" -target FastMoji -configuration Release -showBuildSettings 2>/dev/null)"
APP_SIGN_ID="$(sed -n 's/^ *CODE_SIGN_IDENTITY = //p' <<<"$APP_SETTINGS" | head -1)"
APP_MIN_OS="$(sed -n 's/^ *MACOSX_DEPLOYMENT_TARGET = //p' <<<"$APP_SETTINGS" | head -1)"
VERSION="$(sed -n 's/^ *MARKETING_VERSION = //p' <<<"$APP_SETTINGS" | head -1)"
[[ "$APP_SIGN_ID" == "Developer ID Application" ]] \
  || { echo "error: FastMoji Release CODE_SIGN_IDENTITY is '${APP_SIGN_ID:-unset}', expected 'Developer ID Application' (fix project.pbxproj)." >&2; exit 1; }
[[ "$APP_MIN_OS" == "$MIN_MACOS" ]] \
  || { echo "error: FastMoji Release MACOSX_DEPLOYMENT_TARGET is '${APP_MIN_OS:-unset}', expected '$MIN_MACOS' (fix project.pbxproj)." >&2; exit 1; }
[[ -n "$VERSION" ]] || { echo "error: no MARKETING_VERSION in the Release build settings" >&2; exit 1; }

echo "==> Building FastMoji $VERSION (notary profile: $PROFILE)"

# --- 2. Archive ------------------------------------------------------------
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild -project "$PROJECT" -scheme FastMoji \
  -configuration Release \
  -archivePath "$ARCHIVE" archive

# --- 3. Extract the Developer-ID-signed app from the archive ---------------
# The Release config signs directly with Developer ID + hardened runtime + a secure timestamp,
# so the archived app is already distribution-ready; no `xcodebuild -exportArchive` needed.
# Copy the app out with ditto (preserves bundle structure + signatures; never cp -R, which would
# copy nested symlinks verbatim and dangle).
mkdir -p "$EXPORT_DIR"
ditto "$ARCHIVE/Products/Applications/FastMoji.app" "$APP"
# Sanity-gate the extracted app before the (slow) notarization round-trip. Capture codesign
# output into a var first: piping `codesign | grep -q` trips `set -o pipefail` — grep -q exits
# on first match, SIGPIPEs codesign (exit 141), and the pipeline is wrongly seen as failed.
SIGN_INFO="$(codesign -dvvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$SIGN_INFO" \
  || { echo "error: extracted app is not Developer ID signed" >&2; exit 1; }
grep -q "flags=.*runtime" <<<"$SIGN_INFO" \
  || { echo "error: extracted app lacks the hardened runtime — notarization will reject it" >&2; exit 1; }
ENTITLEMENTS="$(codesign -d --entitlements - "$APP" 2>/dev/null || true)"
if grep -q "get-task-allow" <<<"$ENTITLEMENTS"; then
  echo "error: app carries get-task-allow (Debug entitlement) — instant notarization reject" >&2; exit 1
fi
BUILT_MIN_OS="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist" 2>/dev/null || true)"
[[ "$BUILT_MIN_OS" == "$MIN_MACOS" ]] \
  || { echo "error: built app LSMinimumSystemVersion is '${BUILT_MIN_OS:-unset}', expected '$MIN_MACOS'" >&2; exit 1; }
BUILT_ED_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist" 2>/dev/null | tr -d '[:space:]' || true)"
[[ -n "$BUILT_ED_KEY" ]] \
  || { echo "error: built app has an empty SUPublicEDKey — the Info.plist merge dropped it" >&2; exit 1; }
echo "==> Extracted Developer-ID-signed app from archive"

# --- 3b. Guard against a blank-icon build ----------------------------------
test -f "$APP/Contents/Resources/AppIcon.icns" \
  || { echo "error: AppIcon.icns missing — the AppIcon asset did not compile." >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$APP/Contents/Info.plist" >/dev/null \
  || { echo "error: CFBundleIconName missing from Info.plist." >&2; exit 1; }
echo "==> App icon compiled OK"

# --- 4. Re-sign Sparkle's nested helpers with Developer ID + secure timestamp ----
# The archive signs the app and its frameworks, but leaves Sparkle's deeply nested code
# (Updater.app, Autoupdate, the two XPC services) ADHOC-signed with no secure timestamp —
# notarization rejects exactly those 4. Sign inside-out (nested code first → framework → outer
# app; touching nested code breaks every seal above it). --preserve-metadata=entitlements keeps
# each helper's entitlements while adding Developer ID + secure timestamp + hardened runtime.
# Resolve the version letter (Current → e.g. B) so a future Sparkle bump that changes it does
# not silently skip these paths. Layout verified for Sparkle 2.10.0.
SPK="$APP/Contents/Frameworks/Sparkle.framework"
SPKV="$SPK/Versions/$(readlink "$SPK/Versions/Current" 2>/dev/null || echo B)"
resign() { codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
  --sign "Developer ID Application" "$1"; }
resign "$SPKV/XPCServices/Downloader.xpc"
resign "$SPKV/XPCServices/Installer.xpc"
resign "$SPKV/Updater.app"
resign "$SPKV/Autoupdate"
resign "$SPK"        # re-seal the framework over the re-signed helpers
resign "$APP"        # re-seal the outer app over the re-signed framework
codesign --verify --deep --strict "$APP" \
  || { echo "error: deep signature verification failed after re-signing Sparkle" >&2; exit 1; }
echo "==> Re-signed Sparkle nested helpers (Developer ID + timestamp)"

# --- 5. Notarize + staple the app, then ship-zip it ------------------------
# The first zip is a THROWAWAY upload for notarytool; the file we ship is the re-zip AFTER
# stapling (the staple writes the ticket into the .app, not the zip).
( cd "$EXPORT_DIR" && ditto -c -k --keepParent FastMoji.app "FastMoji-$VERSION.zip" )
notarize "$EXPORT_DIR/FastMoji-$VERSION.zip"
( cd "$EXPORT_DIR" \
  && xcrun stapler staple FastMoji.app \
  && rm -f "FastMoji-$VERSION.zip" \
  && ditto -c -k --keepParent FastMoji.app "FastMoji-$VERSION.zip" )
spctl -a -vv -t exec "$APP"
echo "==> Notarized + stapled the app"

# --- 6. Build the notarized DMG (manual-download asset) --------------------
# A raw .zip breaks when users extract it with a third-party unarchiver (._* files pollute
# Sparkle.framework's seal → Gatekeeper malware warning). A DMG is drag-to-install: Finder
# copies the bundle verbatim, so the seal always survives. Built from the already-stapled app.
( cd "$EXPORT_DIR"
  rm -rf dmg-stage && mkdir dmg-stage
  ditto FastMoji.app dmg-stage/FastMoji.app
  ln -s /Applications dmg-stage/Applications
  hdiutil create -volname "FastMoji" -srcfolder dmg-stage -ov -format UDZO "FastMoji-$VERSION.dmg"
  rm -rf dmg-stage
  # A DMG is a container, not an executable: --timestamp, no hardened runtime.
  codesign --force --timestamp --sign "Developer ID Application" "FastMoji-$VERSION.dmg"
  notarize "FastMoji-$VERSION.dmg"
  xcrun stapler staple "FastMoji-$VERSION.dmg"
  spctl -a -t open --context context:primary-signature -v "FastMoji-$VERSION.dmg"
  xcrun stapler validate "FastMoji-$VERSION.dmg" )
echo "==> Notarized + stapled the DMG"

# --- 7. Done ---------------------------------------------------------------
echo
echo "Done. Notarized + stapled artifacts:"
echo "  zip : $EXPORT_DIR/FastMoji-$VERSION.zip"
echo "  dmg : $EXPORT_DIR/FastMoji-$VERSION.dmg"
echo
echo "Next: scripts/publish-release.sh $EXPORT_DIR/FastMoji-$VERSION.zip"
echo "      then scripts/publish-appcast.sh $EXPORT_DIR/FastMoji-$VERSION.zip"
