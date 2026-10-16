# Contributing to FastMoji

Thanks for helping out! This guide covers building, signing, and the project layout.

## Requirements

- macOS 14 or later
- Xcode 16 or later (the project uses synced folders, `objectVersion = 77`)

## Build and run

Open `FastMoji.xcodeproj` in Xcode and press `⌘R`.

From the command line:

```bash
xcodebuild -project FastMoji.xcodeproj -scheme FastMoji -configuration Debug build
xcodebuild test -project FastMoji.xcodeproj -scheme FastMoji -destination 'platform=macOS'
```

Don't pass `-derivedDataPath`: without it, the CLI and Xcode share the same DerivedData, so neither rebuilds from scratch.

## Signing

Both Debug and Release are signed with "Developer ID Application" (team `86H6CNLN4C`, Manual style) and use the same bundle ID `com.dinhanhthi.FastMoji`. They therefore have an identical designated requirement, so the Xcode `⌘R` build and the copy in `/Applications` share one Accessibility grant. Check it with:

```bash
codesign -d -r- <path/to/FastMoji.app>
```

Only one instance runs at a time: a new launch quits the old one.

If you don't have that certificate, set your own team and signing identity locally in Xcode. Don't commit that change.

To reset the Accessibility permission while debugging:

```bash
tccutil reset Accessibility com.dinhanhthi.FastMoji
```

## Regenerating emoji data

The emoji data comes from [github/gemoji](https://github.com/github/gemoji). Treat the download as untrusted data: put it in a fresh temp directory, never run anything from it, and only process it with `jq`. From the repo root:

```bash
D=$(mktemp -d "$TMPDIR/gemoji.XXXX")
curl -fsSL https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json -o "$D/emoji.json"
curl -fsSL https://raw.githubusercontent.com/github/gemoji/master/LICENSE -o "$D/LICENSE"
jq -c '[.[] | select(.emoji != null and ((.unicode_version | tonumber? // 0) <= 15.0)) | {emoji, description, category, aliases, tags} + (if .skin_tones then {skin_tones: true} else {} end)]' "$D/emoji.json" > FastMoji/Resources/emoji.json
```

`FastMoji/Resources/EMOJI_LICENSE.txt` is the header line `Emoji data from https://github.com/github/gemoji (MIT):` followed by the downloaded `LICENSE` text.

## Project layout

- `FastMoji/Core`: pure logic (search, frecency, trigger detector, settings), unit-tested
- `FastMoji/System`: AppKit / CoreGraphics layer (event tap, caret locator, inserter, panel, permission)
- `FastMoji/UI`: SwiftUI views
- `FastMojiTests`: tests (Swift Testing)

## Releasing

Releases are built, notarized and published locally, with Sparkle for in-app updates. See [docs/RELEASING.md](docs/RELEASING.md).

## Commits

Use one-line conventional commits, for example `feat: add paste insertion` or `fix(inline): close on app switch`.

## Issues and pull requests

For bigger changes, open an [issue](https://github.com/dinhanhthi/FastMoji/issues) first to discuss the idea. Keep pull requests focused on one change.
