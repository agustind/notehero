# NoteHero

A tiny native macOS menu bar app for quick notes. Hit a shortcut from anywhere, type to search,
press ↵ to open a note, or keep typing and press ↵ to create one.

## Features

- **Search first.** The popover opens with the search focused. The list updates as you type,
  matching notes that contain every word you typed, with title matches first.
- **Create from the search box.** When nothing matches, ↵ creates a note titled with your search
  and leaves the cursor below it, so you can keep typing.
- **Global shortcut.** ⌃⌥N by default. Record a different one in Settings (click the cog or
  press ⌘,).
- **Autosave.** Notes are saved as you type. A note you empty is removed when you leave it.
- **Appearance.** System, light or dark.
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

It requires an Apple Silicon Mac.

## Where notes are stored

In a SQLite database at `~/Library/Application Support/com.agudondo.notehero/notes.db`.

## Development

Built with [tinyjs](https://tinyjs.app).

```sh
tinyjs dev    # run with hot reload
tinyjs build  # dist/NoteHero.app (ad-hoc signed)
```

- `src/main.js`: backend (SQLite storage, tray icon, global shortcut, window placement)
- `src/frontend/`: the popover UI (search, editor, settings)

### Signed and notarized release builds

With a Developer ID Application certificate in your keychain and a `notarytool` profile:

```sh
export TINYJS_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
export TINYJS_NOTARY_PROFILE=<profile>
tinyjs build --dmg
tinyjs notarize --dmg
```
