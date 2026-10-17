# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Settings → Ignored: lists of apps and websites where FastMoji stays out of the way. In an ignored app, the inline trigger and the hotkey are off and their keys reach the app untouched. On an ignored website (and its subdomains), the inline trigger is off; the hotkey still works. The menubar works everywhere.
- The search panel has an Ignore button next to Settings: it adds the current app, or the current website in a browser, to Settings → Ignored.
- Inline trigger: type the full alias with a closing colon, e.g. `::smile:`, to insert the emoji instantly without Return or Tab.
- Settings → Aliases: custom aliases that insert your own text, e.g. `shrug` for `¯\_(ツ)_/¯`. Type `::shrug:` or search for the alias. Custom aliases win over built-in ones. The add form sits above the list; each alias has an Edit button that loads it into the form, which then reads Update (with a Cancel button).
- Symbols (macOS keys `⌘` `⌥` `⇧` `⌃`, arrows, currency, math, typography) and kaomoji, with segmented Emoji / Symbols / Kaomoji tabs (the highlight slides to the selected tab) and a category bar to jump between sections, with an underline under the current one.
- Settings → General → Content: toggles to turn Emoji, Symbols and Kaomoji on or off (all on by default; at least one stays on). Turned-off kinds are hidden from the pickers, search and `::alias:`; custom aliases always work.
- Search in English, Vietnamese, French and Spanish, with accents optional (e.g. `::cuoi`).
- Emoji up to Unicode 17. Only the emoji your macOS version can display are shown.
- Emoticon conversion: emoticons that end with a symbol, like `:)` `;)` `:(` `:'(` `:|` `^^`, become emoji as soon as you type them; those that end with a letter or digit, like `:D` `:P` `:O` `xD` `<3` `</3`, convert when followed by a space or punctuation (not Return). An emoticon must start after a space, an opening bracket or quote, a new line, or a pause. It is never converted inside inline code (between backticks), in password fields, in ignored apps and websites, or while an input method is active. Press Backspace right after a conversion to get the typed text back. Off by default; turn it on in Settings → Triggers.
- Text arrows and symbols: `->` becomes →, `=>` ⇒, `<-` ←, `<->` ↔, `<=>` ⇔, `>=` ≥, `<=` ≤ and `--` an em dash —, with the same rules as emoticons and the same Backspace undo. `--` converts only when followed by a space or punctuation, so `--help`, `---` and `-->` stay as typed. Off by default; turn it on in Settings → Triggers. It also changes code such as `=>`, `->`, `>=` and `<=`.
- A Check for Updates icon button in the menubar popover, next to Settings.
- Pause FastMoji for 1 hour from the menubar popover; a Paused row shows when it ends and has a Resume button.
- Password fields are skipped: the inline trigger, the hotkey, emoticon conversion and text arrows do nothing there.
- Secure Input indicator: while another app turns on Secure Input, the menubar icon shows a lock and the popover says the typing triggers are paused.
- A welcome window, shown once after installing or updating, with the three ways to use FastMoji, the Accessibility status and a test field.
- Settings → General: a "Show Welcome…" button to open the welcome window again.

### Changed

- New app logo, now in the macOS 26 icon format. The menubar shows the colored logo instead of a smiley symbol.
- FastMoji shows in the Dock while its Settings window is open.
- Emoji data now comes from emojibase 18.0 (was gemoji).
- Search ignores accents, and matches must start a word or be contiguous, so there are fewer junk results. Tags and keywords (in every language) match only when the search text appears in them as is, never as scattered letters.
- Long text is typed in chunks so it is not cut off.
- The picker is smaller: about 360 pt wide (was 400) with smaller cells. In the menubar popover, Settings is now an icon button.
- Some emoji moved category, e.g. 🦀 🦞 🦐 🦑 🦪 are now in Animals & Nature.

## [0.1.2] - 2026-10-16

### Added

- The About panel now links to the project on GitHub.
- The search panel (inline trigger and hotkey) has Settings and Quit buttons next to the search field. Quit asks for confirmation first.

### Changed

- The magnifying glass in the search panel is larger.
- The Settings and Quit buttons in the search panel are circular, and always shown whether or not the menubar is on (they replace the footer that only appeared with the menubar off).
- Settings: the Menubar description now says that turning it off also hides the menubar icon.

## [0.1.1] - 2026-10-16

### Added

- A GitHub link in the Settings sidebar, under the version number.

### Changed

- Settings: each section's description now sits right below its title instead of at the bottom of the section.

## [0.1.0] - 2026-10-16

### Added

- Inline trigger: type `::` followed by a search term in any text field, then press Return or Tab to replace it with the emoji. The trigger sequence is customizable.
- Hotkey `⌘;` opens a search panel at the text caret; the shortcut is customizable.
- Menubar icon with a search popover.
- Fuzzy search by name, alias and tag, with a "Frequently Used" section when the search is empty.
- Insert, copy, or both, chosen per trigger; insert by typing or by pasting.
- Launch at login, and an option to hide the menubar icon.
- A skin tone setting for people and hand emoji.
- Automatic update checks; "Check for Updates…" in Settings and an Update button in the menubar popover when a new version is available.
