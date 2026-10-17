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

The emoji data comes from [emojibase-data](https://github.com/milesj/emojibase) (MIT), whose labels, keywords and CLDR shortcodes come from [Unicode CLDR](https://cldr.unicode.org) (Unicode License v3). From the repo root:

```bash
scripts/regenerate-emoji-data.sh
```

It rewrites `FastMoji/Resources/emoji.json` and `FastMoji/Resources/EMOJI_LICENSE.txt`. Review the diff and commit it yourself.

- **Pinned:** the emojibase-data 18.0.0 npm tarball, checked against its SHA-256. To update, change the version and hash at the top of the script (and `MAX_EMOJI_VERSION` once macOS ships newer emoji).
- **Untrusted download:** the tarball goes into a fresh `mktemp -d` directory, removed on exit. Nothing from it is executed: it is only extracted with `tar` and read with `jq`.
- **Rows:** English label, tags, github and CLDR shortcodes, plus Vietnamese, French and Spanish keywords and shortcodes. Components, regional indicators and emoji newer than 17.0 are left out (1914 rows for 18.0.0). Each alias belongs to exactly one emoji, by priority github > en > vi > fr > es.
- **Check:** before writing, the script checks that every glyph and alias of the previous `emoji.json` (git `HEAD`, else the file on disk) still resolves to the same glyph. It aborts otherwise, so saved history and old aliases keep working.
- **`--slurpfile`:** pass the data files to `jq` with `--slurpfile` (the value arrives wrapped in an array, `$x[0]`). `--argjson "$(cat file)"` overflows the shell's argument limit with these files.

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
