# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Settings → Ignored: lists of apps and websites where FastMoji stays out of the way. In an ignored app, the inline trigger and the hotkey are off and their keys reach the app untouched. On an ignored website (and its subdomains), the inline trigger is off; the hotkey still works. The menubar works everywhere.
- The search panel has an Ignore button next to Settings: it adds the current app, or the current website in a browser, to Settings → Ignored.

### Changed

- New app logo, now in the macOS 26 icon format. The menubar shows the colored logo instead of a smiley symbol.
- FastMoji shows in the Dock while its Settings window is open.

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
