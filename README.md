<p align="center">
  <img src="assets/only_object.png" width="128" alt="FastMoji logo">
</p>

<h1 align="center">FastMoji</h1>

<p align="center">A simple, fast way to insert emoji anywhere on macOS.</p>

<p align="center">
  <a href="https://github.com/dinhanhthi/FastMoji/releases/latest"><img src="https://img.shields.io/badge/Download-macOS%2014%2B-black?style=for-the-badge&logo=apple" alt="Download"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/Contributing-guide-blue?style=for-the-badge" alt="Contributing"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License"></a>
</p>

## How to use

- **Inline**: type `::` followed by a search term (e.g. `::smile`) in any text field, then press Enter or Tab to replace it with the emoji. Type the full alias with a closing colon (e.g. `::smile:`) to insert it instantly.
- **Hotkey**: press `⌘;` to open a popover at the caret, search, and press Enter to insert.
- **Menubar**: click the menubar icon, search, and press Enter to copy the emoji.

In Cocoa apps, `⌘;` replaces the "Check Document Now" shortcut (Edit → Spelling and Grammar). You can change it in Settings → Triggers.

## Features

- Fuzzy search by name, alias and tag
- Instant insert with `::alias:`
- Custom aliases for your own text, e.g. `¯\_(ツ)_/¯` for `shrug`; add or edit them in Settings → Aliases
- Symbols (macOS keys `⌘` `⌥` `⇧` `⌃`, arrows, currency, math, typography) and kaomoji, with segmented Emoji / Symbols / Kaomoji tabs and a category bar that underlines the current section
- Turn Emoji, Symbols or Kaomoji off in Settings → General → Content to hide them from the pickers, search and `::alias:` (custom aliases always work)
- Search in English, Vietnamese, French and Spanish; accents are optional (e.g. `::cuoi`)
- Emoji up to Unicode 17, showing only those your macOS can display
- "Frequently Used" section when the search is empty
- Insert, copy, or both, chosen per trigger
- Customizable inline trigger and hotkey
- Insert by typing or by pasting
- Optional emoticon conversion, e.g. `:)` → 🙂 as you type it, `:D` → 😃 after a space or punctuation; Backspace right after undoes it (off by default, Settings → Triggers)
- Optional text arrows and symbols, e.g. `->` → →, `<=>` → ⇔, `>=` → ≥, `<=` → ≤, `--` → — (em dash, after a space or punctuation); Backspace right after undoes it (off by default, Settings → Triggers; it also changes code)
- Ignore FastMoji in chosen apps (inline trigger and hotkey) and on chosen websites (inline trigger)
- Pause FastMoji for 1 hour from the menubar
- Password fields are skipped
- Secure Input indicator in the menubar icon and popover
- Welcome window with a test field (reopen it from Settings → General)
- Launch at login
- Hide the menubar icon (reopen FastMoji from Finder or Spotlight to get back to Settings)

## Permissions

FastMoji needs **Accessibility** access to read the caret position and type the emoji into the current app. Grant it from Settings (or in System Settings → Privacy & Security → Accessibility). FastMoji never records keystrokes.

While another app turns on Secure Input (password fields, Terminal's Secure Keyboard Entry), macOS hides keystrokes from FastMoji, so the typing triggers pause. The menubar icon and popover show when this happens.

The inline `::` trigger is paused while an input method such as Vietnamese Telex is active; use `⌘;` instead.

## Privacy

Everything stays on your Mac. The only network access is the update check (Sparkle). FastMoji never records keystrokes.

## Requirements

macOS 14 or later.

## Credits

Emoji data from [emojibase](https://github.com/milesj/emojibase) (MIT) and [Unicode CLDR](https://cldr.unicode.org) annotations (Unicode License v3), see [FastMoji/Resources/EMOJI_LICENSE.txt](FastMoji/Resources/EMOJI_LICENSE.txt). The symbol and kaomoji lists are FastMoji's own (symbol keywords in other languages come from CLDR).

To build from source, see [CONTRIBUTING.md](CONTRIBUTING.md).
