# Changelog

## Unreleased

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
