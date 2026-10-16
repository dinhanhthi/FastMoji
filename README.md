<p align="center">
  <img src="assets/logo_256.png" width="128" alt="FastMoji logo">
</p>

<h1 align="center">FastMoji</h1>

<p align="center">A simple, fast way to insert emoji anywhere on macOS.</p>

<p align="center">
  <a href="https://github.com/dinhanhthi/FastMoji/releases/latest"><img src="https://img.shields.io/badge/Download-macOS%2014%2B-black?style=for-the-badge&logo=apple" alt="Download"></a>
  <a href="https://github.com/dinhanhthi/FastMoji/issues"><img src="https://img.shields.io/github/issues/dinhanhthi/FastMoji?style=for-the-badge" alt="Issues"></a>
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/Contributing-guide-blue?style=for-the-badge" alt="Contributing"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License"></a>
</p>

## How to use

- **Inline**: type `::` followed by a search term (e.g. `::smile`) in any text field, then press Enter or Tab to replace it with the emoji.
- **Hotkey**: press `⌘;` to open a popover at the caret, search, and press Enter to insert.
- **Menubar**: click the menubar icon, search, and press Enter to copy the emoji.

## Features

- Fuzzy search by name, alias and tag
- "Frequently Used" section when the search is empty
- Insert, copy, or both, chosen per trigger
- Customizable inline trigger and hotkey
- Insert by typing or by pasting
- Launch at login
- Hide the menubar icon (reopen FastMoji from Finder or Spotlight to get back to Settings)

## Permissions

FastMoji needs **Accessibility** access to read the caret position and type the emoji into the current app. Grant it from Settings (or in System Settings → Privacy & Security → Accessibility). FastMoji never records keystrokes.

The inline `::` trigger is paused while an input method such as Vietnamese Telex is active; use `⌘;` instead.

## Requirements

macOS 14 or later.

## Credits

Emoji data from [github/gemoji](https://github.com/github/gemoji) (MIT), see [FastMoji/Resources/EMOJI_LICENSE.txt](FastMoji/Resources/EMOJI_LICENSE.txt).

To build from source, see [CONTRIBUTING.md](CONTRIBUTING.md).
