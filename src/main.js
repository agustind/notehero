// NoteHero backend: notes live in SQLite, the tray icon and the global
// hotkey summon the popover window under the menu-bar icon.
import { Database } from 'tjs:sqlite';

const DEFAULT_HOTKEY = 'ctrl+alt+n';
// 0.1.0 shipped under this bundle id; its data folder is migrated on launch
const OLD_ID = 'com.agudondo.notehero';
const HOTKEY_ID = 'summon';

let db = null;
let hotkey = DEFAULT_HOTKEY;
// Clicking the tray icon while the popover is open first blurs (and hides)
// the window, then delivers the click — remember when that happened so the
// click doesn't immediately re-open it.
let lastBlurHide = 0;

async function exists(path) {
  try { await tjs.stat(path); return true; } catch { return false; }
}

// Copy notes and settings from the 0.1.0 data folder the first time this
// build runs. The old folder is left in place as a backup.
async function migrateData(app) {
  const dir = app.paths.data;
  const oldDir = dir.replace(/[^/]+\/?$/, OLD_ID);
  if (oldDir === dir || await exists(dir + '/notes.db') || !await exists(oldDir + '/notes.db')) return;
  await tjs.makeDir(dir, { recursive: true });
  for (const f of ['notes.db', 'store.json']) {
    if (await exists(oldDir + '/' + f)) await tjs.writeFile(dir + '/' + f, await tjs.readFile(oldDir + '/' + f));
  }
}

// One shared promise, so concurrent first calls (init and the page's first
// list) don't each open a database — or open one before the migration ran.
let dbReady = null;
function openDb(app) {
  return dbReady ??= (async () => {
    await migrateData(app);
    const dir = app.paths.data;
    await tjs.makeDir(dir, { recursive: true });
    db = new Database(dir + '/notes.db');
    db.exec(`CREATE TABLE IF NOT EXISTS notes (
      id INTEGER PRIMARY KEY,
      body TEXT NOT NULL DEFAULT '',
      created INTEGER NOT NULL,
      updated INTEGER NOT NULL
    )`);
    return db;
  })();
}

function query(sql, ...args) {
  const st = db.prepare(sql);
  try { return st.all(...args); } finally { st.finalize(); }
}

export const api = {
  async list(_, app) {
    await openDb(app);
    return query('SELECT id, body, created, updated FROM notes ORDER BY updated DESC');
  },

  async create({ body = '' }, app) {
    await openDb(app);
    const now = Date.now();
    return query('INSERT INTO notes (body, created, updated) VALUES (?, ?, ?) RETURNING id, body, created, updated',
      body, now, now)[0];
  },

  async save({ id, body }, app) {
    await openDb(app);
    const now = Date.now();
    query('UPDATE notes SET body = ?, updated = ? WHERE id = ?', body, now, id);
    return { id, updated: now };
  },

  async remove({ id }, app) {
    await openDb(app);
    query('DELETE FROM notes WHERE id = ?', id);
    return true;
  },

  async getHotkey() {
    return { combo: hotkey, default: DEFAULT_HOTKEY };
  },

  async setHotkey({ combo }, app) {
    combo = String(combo || DEFAULT_HOTKEY).toLowerCase();
    app.hotkey.unregister(HOTKEY_ID);
    app.hotkey.register(HOTKEY_ID, combo);
    hotkey = combo;
    await app.store.set('hotkey', combo);
    return { combo };
  },

  async hide(_, app) {
    app.hide();
    return true;
  },
};

async function summon(app) {
  const st = await app.getWinState();
  if (st.visible && st.focused) {
    app.hide();
    return;
  }
  const spot = await app.tray.position();
  if (spot) {
    const w = st.outer?.width || st.width;
    const maxX = (st.screen?.width || 1e5) - w - 8;
    const x = Math.max(8, Math.min(Math.round(spot.x + spot.width / 2 - w / 2), maxX));
    app.setPosition(x, Math.round(spot.y + spot.height + 4));
  } else {
    app.center();
  }
  app.show();
  app.push('summon');
}

export async function init(app) {
  await openDb(app);
  app.tray.set({
    icon: 'sf:note.text',
    tooltip: 'NoteHero',
    primaryAction: true,
    menu: [
      { id: 'open', label: 'Open NoteHero' },
      { id: 'settings', label: 'Settings…' },
      { id: 'about', label: 'About NoteHero' },
      { separator: true },
      { id: 'quit', label: 'Quit NoteHero' },
    ],
  });
  app.setHideOnClose(true);
  // Follow the user onto whatever Space / fullscreen app they're in.
  app.setAllSpaces(true);
  app.setLevel('floating');

  hotkey = (await app.store.get('hotkey')) || DEFAULT_HOTKEY;
  app.hotkey.register(HOTKEY_ID, hotkey);
}

export function onTray(id, app) {
  if (id === null) {
    if (Date.now() - lastBlurHide < 400) return;
    summon(app);
  } else if (id === 'open') {
    summon(app);
  } else if (id === 'settings') {
    summon(app).then(() => app.push('open-settings'));
  } else if (id === 'about') {
    summon(app).then(() => app.push('about'));
  } else if (id === 'quit') {
    app.quit();
  }
}

export function onHotkey(id, app) {
  if (id === HOTKEY_ID) summon(app);
}

// Behave like a popover: clicking anywhere else puts it away.
export function onWindowState(info, app) {
  if (info.win === 'main' && info.focused === false) {
    lastBlurHide = Date.now();
    app.hide();
  }
}
