# Changelog

## 0.2.1 — 2026-10-08

### Added
- **Checklists.** Type `.-` at the start of a line to turn it into a checkbox (☐), and click the
  box to check it off (☑). Checked items are dimmed and struck through. Press ↵ on a checklist
  line to start the next item, or on an empty item to end the list. Checkboxes are saved as plain
  ☐ / ☑ characters, so they show up in search and copy as text.

## 0.2.0 — 2026-09-29

### Changed
- **Native app.** NoteHero is rewritten in Swift (AppKit + SwiftUI) instead of tinyjs. Note editing
  is native, with undo, spell check and input methods. The app is
  under 1 MB (was 9 MB). Everything else works as before.
- **Your notes carry over.** The app reads the same notes database. Your shortcut, appearance and
  font settings are imported from the old version on first launch.
- The Appearance setting now applies to the whole popover, so the translucent background
  follows it too.
- If macOS won't register a new shortcut, Settings says so and the previous one stays active.
- **Notes open at the top**, with the cursor at the start. A note you just created still puts the
  cursor below its title.
- Requires macOS 14 or later.

## 0.1.4 — 2026-09-27

### Added
- **Editor font settings.** Pick the typeface, size and line height of the note editor in
  Settings, with a live preview. Choose from SF Mono, Menlo, Monaco, Courier New, San Francisco,
  Helvetica Neue, Avenir Next, New York and Georgia, or type the name of any installed font.

### Changed
- **Monospace by default.** Notes now open in SF Mono at 13 pt with a 1.5 line height.

## 0.1.3 — 2026-09-25

### Changed
- **New dark app icon** in the tinyjs style: a soft-blue note page on navy, also shown in the
  About screen.

## 0.1.2 — 2026-09-25

### Changed
- **New app icon:** an amber note with a magnifying glass, also shown in the About screen.

## 0.1.1 — 2026-09-25

### Changed
- **Data folder** is now `~/Library/Application Support/io.github.agustind.notehero`, matching
  the app's new bundle id. Notes and settings from 0.1.0 are copied over on first launch; the old
  `com.agudondo.notehero` folder is left in place as a backup.

## 0.1.0 — 2026-09-25

First release.

- **Menu bar popover.** Click the menu bar icon to open a search box above a list of all your
  notes, newest first.
- **Search as you type.** Notes containing every word you type are listed, with matches in the
  title first and highlighted.
- **Keyboard first.** ↑/↓ to select, ↵ to open, esc to go back or close. When nothing matches, ↵
  creates a note titled with your search and puts the cursor below it.
- **Global shortcut.** Open NoteHero from anywhere (⌃⌥N by default, changeable in Settings).
- **Delete with confirmation.** ⌘⇧⌫ deletes the selected or open note after you confirm.
- **Autosave.** Notes are saved as you type, in a local SQLite database.
- **Appearance.** Follow the system, or force light or dark.
- **Start at login.** Optionally launch the app when you log in.
