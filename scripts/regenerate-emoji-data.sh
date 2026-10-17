#!/usr/bin/env bash
#
# regenerate-emoji-data.sh — Rebuild FastMoji/Resources/emoji.json and EMOJI_LICENSE.txt
# from the emojibase-data npm package, and FastMoji/Resources/symbols.json from our own
# scripts/data/symbols.json plus the cldr-annotations-full npm package; validate the
# hand-written FastMoji/Resources/kaomoji.json (CONTRIBUTING.md "Regenerating emoji data").
#
# Downloads are untrusted data: they go into a fresh temp directory, are checked against a
# pinned SHA-256, and are only read by jq. Nothing from them is executed.
#
# Each output row: emoji, description (en label), category (gemoji-style group name),
# aliases (github, en cldr, vi, fr, es cldr shortcodes; each alias belongs to one emoji),
# tags (en), keywords (vi/fr/es labels and tags, omitted when empty), version,
# skin_tones (true when the emoji takes a skin tone, omitted otherwise), and
# skin_tones_version (newest version of its toned forms, only when newer than version).
#
# Before writing, the script checks that every glyph and alias of the previous emoji.json
# (git HEAD, else the file on disk) still resolves to the same glyph, and aborts otherwise.
#
# Symbols: each row of scripts/data/symbols.json gets the vi/fr/es CLDR annotation keywords
# and names as `keywords`. Symbols whose scalars, ignoring U+FE0F, equal an emoji glyph are
# dropped (e.g. © vs ©️). Aliases must be unique across emoji, symbols and kaomoji.
#
# Usage:
#   scripts/regenerate-emoji-data.sh
#
set -euo pipefail

VERSION="18.0.0"
TARBALL_URL="https://registry.npmjs.org/emojibase-data/-/emojibase-data-$VERSION.tgz"
TARBALL_SHA256="ed207c64f31baab5db419686135be3696bbd196a88228a3564383d7918db8f34"
MAX_EMOJI_VERSION=17

CLDR_VERSION="48.2.0"
CLDR_URL="https://registry.npmjs.org/cldr-annotations-full/-/cldr-annotations-full-$CLDR_VERSION.tgz"
CLDR_SHA256="28576e51225deb51e3ddd734b0f824a0079682cb5d8c27faa9f68149317a14d1"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$REPO_ROOT/FastMoji/Resources"
OUT_JSON="$RESOURCES/emoji.json"
OUT_LICENSE="$RESOURCES/EMOJI_LICENSE.txt"
OUT_SYMBOLS="$RESOURCES/symbols.json"
KAOMOJI="$RESOURCES/kaomoji.json"
SYMBOLS_SOURCE="$REPO_ROOT/scripts/data/symbols.json"

for tool in curl shasum tar jq; do
  command -v "$tool" >/dev/null || { echo "error: $tool not found" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Download, verify, extract ---------------------------------------------------------

echo "Downloading emojibase-data $VERSION..."
curl -fsSL --proto '=https' --tlsv1.2 "$TARBALL_URL" -o "$WORK/emojibase-data.tgz"

actual="$(shasum -a 256 "$WORK/emojibase-data.tgz" | cut -d' ' -f1)"
if [[ "$actual" != "$TARBALL_SHA256" ]]; then
  echo "error: SHA-256 mismatch for $TARBALL_URL" >&2
  echo "  expected $TARBALL_SHA256" >&2
  echo "  got      $actual" >&2
  exit 1
fi

# Extract only the files we read (bsdtar refuses absolute paths and "..").
mkdir "$WORK/x"
tar -xzf "$WORK/emojibase-data.tgz" -C "$WORK/x" \
  package/LICENSE \
  package/en/data.json package/en/shortcodes/github.json package/en/shortcodes/cldr.json \
  package/vi/data.json package/vi/shortcodes/cldr.json \
  package/fr/data.json package/fr/shortcodes/cldr.json \
  package/es/data.json package/es/shortcodes/cldr.json
P="$WORK/x/package"

# --- Build emoji.json ------------------------------------------------------------------

# Values passed with --slurpfile arrive wrapped in an array ($x[0]). Never use
# --argjson "$(cat file)": these files overflow the shell's argument limit.
read -r -d '' BUILD <<'JQ' || true
def arr: if . == null then [] elif type == "array" then . else [.] end;
def uniq: reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end);
def by_hex: map({key: .hexcode, value: .}) | from_entries;
{"0": "Smileys & Emotion", "1": "People & Body", "3": "Animals & Nature",
 "4": "Food & Drink", "5": "Travel & Places", "6": "Activities", "7": "Objects",
 "8": "Symbols", "9": "Flags"} as $category
| [$gh[0], $encldr[0], $vicldr[0], $frcldr[0], $escldr[0]] as $tiers
| [$vi[0], $fr[0], $es[0] | by_hex] as $locales
# Group 2 = components (skin tones, hair), group null = regional indicators.
| [.[] | select(.group != null and .group != 2 and .version <= $maxVersion)]
| sort_by(.order)
| . as $rows
# Each alias belongs to the first claim by priority (github > en cldr > vi > fr > es), then order.
| (reduce ([range(0; $tiers | length) as $t | $rows[] | .hexcode as $h
           | $tiers[$t][$h] | arr[] | {alias: ., hex: $h}][]) as $a
     ({}; if has($a.alias) then . else .[$a.alias] = $a.hex end)) as $owner
| [$rows[] | .hexcode as $h
   | ([$locales[][$h] | select(. != null) | (.label // empty), (.tags // [])[]] | uniq) as $keywords
   | {emoji, description: .label, category: $category[.group | tostring],
      aliases: ([$tiers[][$h] | arr[]] | uniq | map(select($owner[.] == $h))),
      tags: (.tags // [])}
     + (if ($keywords | length) > 0 then {keywords: $keywords} else {} end)
     + {version}
     + (if .skins != null then {skin_tones: true} else {} end)
     # Toned forms newer than the base glyph (e.g. Emoji 17 tones for 👯 and 🤼, base 0.6/3).
     + ((.skins // [] | map(.version) | max) as $sv
        | if $sv != null and $sv > .version then {skin_tones_version: $sv} else {} end)]
JQ

jq -c --argjson maxVersion "$MAX_EMOJI_VERSION" \
  --slurpfile gh "$P/en/shortcodes/github.json" \
  --slurpfile encldr "$P/en/shortcodes/cldr.json" \
  --slurpfile vicldr "$P/vi/shortcodes/cldr.json" \
  --slurpfile frcldr "$P/fr/shortcodes/cldr.json" \
  --slurpfile escldr "$P/es/shortcodes/cldr.json" \
  --slurpfile vi "$P/vi/data.json" \
  --slurpfile fr "$P/fr/data.json" \
  --slurpfile es "$P/es/data.json" \
  "$BUILD" "$P/en/data.json" > "$WORK/emoji.json"

# --- Check against the previous emoji.json ---------------------------------------------

if git -C "$REPO_ROOT" show "HEAD:FastMoji/Resources/emoji.json" > "$WORK/previous.json" 2>/dev/null; then
  previous="git HEAD"
elif [[ -f "$OUT_JSON" ]]; then
  cp "$OUT_JSON" "$WORK/previous.json"
  previous="$OUT_JSON"
else
  echo "error: no previous emoji.json to check against" >&2
  exit 1
fi

read -r -d '' CHECK <<'JQ' || true
(.[0] | map({key: .emoji, value: true}) | from_entries) as $glyphs
| ([.[0][] | .emoji as $g | .aliases[] | {key: ., value: $g}] | from_entries) as $alias
| ([.[0][].aliases[]] | group_by(.) | map(select(length > 1) | "duplicate alias \(.[0])"))
  + ([.[0][].category] | unique
     | if . == ([$prev[0][].category] | unique) then [] else ["category set changed: \(.)"] end)
  + [$prev[0][] | .emoji as $g
     | (if $glyphs[$g] then empty else "missing glyph \($g)" end),
       (.aliases[] | select($alias[.] != $g) | "alias \(.) -> \($alias[.] // "nothing"), expected \($g)")]
| .[]
JQ

problems="$(jq -rs --slurpfile prev "$WORK/previous.json" "$CHECK" "$WORK/emoji.json")"
if [[ -n "$problems" ]]; then
  echo "error: new emoji data breaks the previous emoji.json ($previous):" >&2
  echo "$problems" >&2
  exit 1
fi

# --- Build symbols.json ----------------------------------------------------------------

echo "Downloading cldr-annotations-full $CLDR_VERSION..."
curl -fsSL --proto '=https' --tlsv1.2 "$CLDR_URL" -o "$WORK/cldr.tgz"

actual="$(shasum -a 256 "$WORK/cldr.tgz" | cut -d' ' -f1)"
if [[ "$actual" != "$CLDR_SHA256" ]]; then
  echo "error: SHA-256 mismatch for $CLDR_URL" >&2
  echo "  expected $CLDR_SHA256" >&2
  echo "  got      $actual" >&2
  exit 1
fi

mkdir "$WORK/cldr"
tar -xzf "$WORK/cldr.tgz" -C "$WORK/cldr" \
  package/annotations/vi/annotations.json \
  package/annotations/fr/annotations.json \
  package/annotations/es/annotations.json
A="$WORK/cldr/package/annotations"

# Annotation keys are glyphs without U+FE0F; both `default` and `tts` are arrays.
read -r -d '' SYMBOLS <<'JQ' || true
def uniq: reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end);
def bare: gsub("\ufe0f"; "");
($emoji[0] | map({key: (.emoji | bare), value: true}) | from_entries) as $emojiGlyphs
| [$vi[0], $fr[0], $es[0] | .annotations.annotations] as $locales
| [.[] | select($emojiGlyphs[.emoji | bare] | not)
   | (.emoji | bare) as $k
   | ([$locales[][$k] | select(. != null) | (.default // [])[], (.tts // [])[]] | uniq) as $keywords
   | {emoji, description, category, aliases, tags}
     + (if ($keywords | length) > 0 then {keywords: $keywords} else {} end)]
JQ

jq -c \
  --slurpfile emoji "$WORK/emoji.json" \
  --slurpfile vi "$A/vi/annotations.json" \
  --slurpfile fr "$A/fr/annotations.json" \
  --slurpfile es "$A/es/annotations.json" \
  "$SYMBOLS" "$SYMBOLS_SOURCE" > "$WORK/symbols.json"

dropped="$(jq -r --slurpfile out "$WORK/symbols.json" \
  '[$out[0][].emoji] as $kept | [.[].emoji | select(. as $g | $kept | index([$g]) | not)] | join(" ")' \
  "$SYMBOLS_SOURCE")"
if [[ -n "$dropped" ]]; then
  echo "Dropped symbols that are emoji glyphs: $dropped"
fi

# --- Check symbols and kaomoji ---------------------------------------------------------

# Input: [source symbols, built symbols, kaomoji, emoji]. Guillemets are banned (project rule).
read -r -d '' VALIDATE <<'JQ' || true
def bare: gsub("\ufe0f"; "");
def utf16: explode | map(if . > 65535 then 2 else 1 end) | add;
def guillemet: explode | any(. == 171 or . == 187 or . == 8249 or . == 8250);
. as [$source, $symbols, $kaomoji, $emoji]
| ($emoji | map({key: (.emoji | bare), value: true}) | from_entries) as $emojiGlyphs
| ["Keyboard", "Arrows", "Currency", "Math", "Typography", "Checkboxes"] as $symbolCategories
| ([$source[], $kaomoji[]]
   | map(select((.emoji | type) != "string" or (.emoji | length) == 0
                or (.description | type) != "string" or (.description | length) == 0
                or (.category | type) != "string" or (.category | length) == 0
                or (.aliases | type) != "array" or (.tags | type) != "array")
         | "malformed row \(.emoji)")
  + [$source[] | select(.category as $c | $symbolCategories | index([$c]) | not)
     | "symbol \(.emoji): unknown category \(.category)"]
  + ([$source[].emoji] | group_by(.) | map(select(length > 1) | "duplicate symbol \(.[0])"))
  + ([$kaomoji[].emoji] | group_by(.) | map(select(length > 1) | "duplicate kaomoji \(.[0])"))
  + [$source[], $kaomoji[] | .aliases[] | select(type != "string" or (test("^[a-z0-9_+-]{1,64}$") | not))
     | "invalid alias \(.)"]
  + ([$source[].aliases[]] | group_by(.) | map(select(length > 1) | "duplicate symbol alias \(.[0])"))
  + ([$emoji[].aliases[], $symbols[].aliases[], $kaomoji[].aliases[]] | group_by(.)
     | map(select(length > 1) | "alias \(.[0]) used more than once across emoji, symbols, kaomoji"))
  + [$kaomoji[] | .emoji as $k
     | (if ($k | utf16) > 30 then "kaomoji \($k): longer than 30 UTF-16 units" else empty end),
       (if ($k | explode | any(. < 32 or (. >= 127 and . < 160) or . == 8232 or . == 8233))
        then "kaomoji \($k): control or line break character" else empty end),
       (if $emojiGlyphs[$k | bare] then "kaomoji \($k) is an emoji glyph" else empty end)]
  + [$symbols[] | select($emojiGlyphs[.emoji | bare]) | "symbol \(.emoji) is an emoji glyph"]
  + [$source[], $kaomoji[] | select([.emoji, .description, .category, .aliases[], .tags[]] | any(guillemet))
     | "guillemet in \(.emoji)"])
| .[]
JQ

problems="$(jq -rn --slurpfile s "$SYMBOLS_SOURCE" --slurpfile b "$WORK/symbols.json" \
  --slurpfile k "$KAOMOJI" --slurpfile e "$WORK/emoji.json" \
  "[\$s[0], \$b[0], \$k[0], \$e[0]] | $VALIDATE")"
if [[ -n "$problems" ]]; then
  echo "error: symbols.json or kaomoji.json is invalid:" >&2
  echo "$problems" >&2
  exit 1
fi

# --- Write outputs ---------------------------------------------------------------------

mv "$WORK/emoji.json" "$OUT_JSON"
mv "$WORK/symbols.json" "$OUT_SYMBOLS"

{
  echo "Emoji data from emojibase-data $VERSION, https://github.com/milesj/emojibase (MIT):"
  echo
  cat "$P/LICENSE"
  echo
  echo "Emoji labels, keywords and CLDR shortcodes in emojibase-data, and the symbol keywords"
  echo "in symbols.json (cldr-annotations-full $CLDR_VERSION), come from the Unicode CLDR"
  echo "project, https://cldr.unicode.org (Unicode License v3):"
  echo
  cat <<'UNICODE'
UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.
UNICODE
} > "$OUT_LICENSE"

echo "Wrote $(jq length "$OUT_JSON") emoji to $OUT_JSON (checked against $previous)."
echo "Wrote $(jq length "$OUT_SYMBOLS") symbols to $OUT_SYMBOLS; $(jq length "$KAOMOJI") kaomoji checked."
echo "Wrote $OUT_LICENSE. Review the diff and commit it yourself."
