# NoteHero

A tiny native macOS menu bar app for quick notes, written in Swift (AppKit + SwiftUI). Hit a
shortcut from anywhere, type to search, press ↵ to open a note, or keep typing and press ↵ to
create one.

## Features

- **Search first.** The popover opens with the search focused. The list updates as you type,
  matching notes that contain every word you typed, with title matches first.
- **Create from the search box.** When nothing matches, ↵ creates a note titled with your search
  and leaves the cursor below it, so you can keep typing.
- **Global shortcut.** ⌃⌥N by default. Record a different one in Settings (click the cog or
  press ⌘,).
- **Autosave.** Notes are saved as you type. A note you empty is removed when you leave it.
- **Appearance.** System, light or dark.
- **Editor font.** Choose the typeface, size and line height in Settings. Notes use SF Mono by
  default, and you can type the name of any installed font.
- **Start at login.** Optionally launch the app when you log in.

## Keyboard

| Where | Keys | Action |
| ----- | ---- | ------ |
| Anywhere | ⌃⌥N (configurable) | Open or close NoteHero |
| Search | ↑ / ↓ | Select a note |
| Search | ↵ | Open the selected note, or create one when nothing matches |
| Search | ⌘↵ | Create a note from the search text |
| Search | ⌘⇧⌫ | Delete the selected note (asks first) |
| Search | esc | Clear the search, then close |
| Note | esc | Back to the list |
| Note | ⌘⇧⌫ | Delete the note (asks first) |
| Anywhere in the popover | ⌘N / ⌘, | New note / Settings |

## Install

1. Download the latest `.dmg` from [Releases](https://github.com/agustind/notehero/releases/latest).
2. Open it and drag **NoteHero** into **Applications**.
3. Launch it. A note icon appears in the menu bar.

It requires an Apple Silicon Mac with macOS 14 or later.

## Where notes are stored

In a SQLite database at `~/Library/Application Support/io.github.agustind.notehero/notes.db`.
Settings are kept in the app's preferences (`io.github.agustind.notehero`).

## Development

A native Swift app (AppKit + SwiftUI), macOS 14 or later. Needs the Xcode command line tools.

```sh
scripts/build.sh                  # dist/NoteHero.app (ad-hoc signed)
open dist/NoteHero.app
```

To try a build without touching your real notes, point it at another folder:

```sh
NOTEHERO_DATA_DIR=/tmp/notehero-dev dist/NoteHero.app/Contents/MacOS/NoteHero
```

- `Sources/NoteHero/main.swift`: menu bar icon, the popover panel and its placement
- `Sources/NoteHero/AppModel.swift`: notes, search, keyboard handling, settings actions
- `Sources/NoteHero/Views.swift`, `TextInputs.swift`: the popover UI (search, editor, settings)
- `Sources/NoteHero/NotesDB.swift`: SQLite storage
- `Sources/NoteHero/HotKey.swift`: the global shortcut
- `Sources/NoteHero/Settings.swift`: data folder, preferences, and migration from older versions
- `Info.plist`: bundle id and version

### Signed and notarized release builds

With a Developer ID Application certificate in your keychain and a `notarytool` profile:

```sh
export NOTEHERO_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
export NOTEHERO_NOTARY_PROFILE=<profile>
scripts/build.sh --notarize       # dist/notehero-<version>.dmg and .zip, notarized and stapled
```
