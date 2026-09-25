const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g,
  (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

let notes = [];        // every note, newest first
let shown = [];        // notes currently in the list
let sel = 0;           // index into `shown`
let current = null;    // note open in the editor
let view = 'list';
let saveTimer = null;

// ---------- helpers ----------

const lines = (body) => body.split('\n').map((l) => l.trim()).filter(Boolean);
const titleOf = (body) => (lines(body)[0] || 'Untitled').replace(/^#+\s*/, '');
const termsOf = (q) => q.toLowerCase().split(/\s+/).filter(Boolean);

function fmtDate(ms) {
  const d = new Date(ms), now = new Date();
  if (d.toDateString() === now.toDateString())
    return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  const opts = { month: 'short', day: 'numeric' };
  if (d.getFullYear() !== now.getFullYear()) opts.year = 'numeric';
  return d.toLocaleDateString([], opts);
}

// escape `text` and wrap every occurrence of any term in <mark>
function highlight(text, terms) {
  if (!terms.length) return esc(text);
  const lower = text.toLowerCase();
  const ranges = [];
  for (const t of terms) {
    for (let i = lower.indexOf(t); i !== -1; i = lower.indexOf(t, i + t.length)) ranges.push([i, i + t.length]);
  }
  ranges.sort((a, b) => a[0] - b[0]);
  let out = '', pos = 0;
  for (const [s, e] of ranges) {
    if (e <= pos) continue;
    const from = Math.max(s, pos);
    out += esc(text.slice(pos, from)) + '<mark>' + esc(text.slice(from, e)) + '</mark>';
    pos = e;
  }
  return out + esc(text.slice(pos));
}

// the line under the title that best shows why this note matched
function snippetOf(body, terms) {
  const rest = lines(body).slice(1);
  if (terms.length) {
    const hit = rest.find((l) => terms.some((t) => l.toLowerCase().includes(t)));
    if (hit) {
      const i = Math.max(0, Math.min(...terms.map((t) => {
        const k = hit.toLowerCase().indexOf(t); return k === -1 ? Infinity : k;
      })) - 30);
      return (i > 0 ? '…' : '') + hit.slice(i);
    }
  }
  return rest.join('  ·  ');
}

// ---------- list view ----------

function filter() {
  const q = $('q').value;
  const terms = termsOf(q);
  if (!terms.length) {
    shown = notes;
  } else {
    shown = notes
      .map((n) => ({ n, lower: n.body.toLowerCase(), title: titleOf(n.body).toLowerCase() }))
      .filter((x) => terms.every((t) => x.lower.includes(t)))
      .sort((a, b) => {
        const ta = terms.every((t) => a.title.includes(t)), tb = terms.every((t) => b.title.includes(t));
        return (tb - ta) || (b.n.updated - a.n.updated);
      })
      .map((x) => x.n);
  }
  sel = 0;
  render(terms);
}

function render(terms = termsOf($('q').value)) {
  const list = $('list'), empty = $('empty');
  list.innerHTML = shown.map((n, i) => `
    <li data-i="${i}" class="${i === sel ? 'sel' : ''}" role="option">
      <span class="title">${highlight(titleOf(n.body), terms)}</span>
      <span class="date">${esc(fmtDate(n.updated))}</span>
      <span class="snippet">${highlight(snippetOf(n.body, terms), terms) || '&nbsp;'}</span>
    </li>`).join('');
  list.hidden = !shown.length;
  empty.hidden = !!shown.length;
  if (!shown.length) {
    const q = $('q').value.trim();
    empty.innerHTML = q
      ? `No notes match. Press <b>↵</b> to create “${esc(q)}”.`
      : `No notes yet. Type a title and press <b>↵</b>.`;
  }
}

function moveSel(delta) {
  if (!shown.length) return;
  sel = Math.max(0, Math.min(shown.length - 1, sel + delta));
  const items = $('list').children;
  for (const li of items) li.classList.toggle('sel', +li.dataset.i === sel);
  items[sel]?.scrollIntoView({ block: 'nearest' });
}

function showList({ reset = false } = {}) {
  if (recording) stopRecording();
  showAbout(false);
  view = 'list';
  $('editorView').hidden = true;
  $('settingsView').hidden = true;
  $('listView').hidden = false;
  if (reset) $('q').value = '';
  filter();
  $('q').focus();
  $('q').select();
}

$('q').addEventListener('input', filter);
$('q').addEventListener('keydown', (e) => {
  if (e.key === 'ArrowDown' || (e.ctrlKey && e.key === 'n')) { e.preventDefault(); moveSel(1); }
  else if (e.key === 'ArrowUp' || (e.ctrlKey && e.key === 'p')) { e.preventDefault(); moveSel(-1); }
  else if (e.key === 'Backspace' && e.metaKey && e.shiftKey) { e.preventDefault(); deleteSelected(); }
  else if (e.key === 'Enter') {
    e.preventDefault();
    if (e.metaKey || !shown.length) createNote($('q').value.trim());
    else openNote(shown[sel]);
  } else if (e.key === 'Escape') {
    e.preventDefault();
    if ($('q').value) { $('q').value = ''; filter(); } else tiny.win.hide();
  }
});
$('list').addEventListener('click', (e) => {
  const li = e.target.closest('li');
  if (li) openNote(shown[+li.dataset.i]);
});
$('gear').addEventListener('click', showSettings);

// ---------- editor ----------

async function createNote(title) {
  const body = title ? title + '\n\n' : '';
  const note = await tiny.api.call('create', { body });
  notes.unshift(note);
  openNote(note);
}

function openNote(note) {
  if (!note) return;
  current = note;
  view = 'editor';
  $('listView').hidden = true;
  $('settingsView').hidden = true;
  $('editorView').hidden = false;
  const ed = $('editor');
  ed.value = note.body;
  $('meta').textContent = 'Edited ' + fmtDate(note.updated);
  $('saved').textContent = '';
  ed.focus();
  ed.setSelectionRange(ed.value.length, ed.value.length);
  ed.scrollTop = ed.scrollHeight;
}

function scheduleSave() {
  clearTimeout(saveTimer);
  $('saved').textContent = 'Editing…';
  saveTimer = setTimeout(flushSave, 400);
}

async function flushSave() {
  clearTimeout(saveTimer);
  saveTimer = null;
  if (!current) return;
  const body = $('editor').value;
  if (body === current.body) return;
  current.body = body;
  const { updated } = await tiny.api.call('save', { id: current.id, body });
  current.updated = updated;
  // most recently edited floats to the top
  notes = [current, ...notes.filter((n) => n !== current)];
  if (view === 'editor') $('saved').textContent = 'Saved';
}

// leave the editor; a note left blank is thrown away
async function closeNote() {
  if (!current) return;
  const note = current;
  if (!$('editor').value.trim()) {
    clearTimeout(saveTimer);
    current = null;
    notes = notes.filter((n) => n !== note);
    await tiny.api.call('remove', { id: note.id });
  } else {
    await flushSave();
    current = null;
  }
}

// ---------- delete (with confirmation) ----------

let confirming = null;   // resolve() of the open confirmation, if any

function confirmDelete(note) {
  $('confirmTitle').textContent = `Delete “${titleOf(note.body)}”?`;
  $('confirm').hidden = false;
  return new Promise((resolve) => {
    confirming = (ok) => { confirming = null; $('confirm').hidden = true; resolve(ok); };
  });
}
$('confirmCancel').addEventListener('click', () => confirming?.(false));
$('confirmOk').addEventListener('click', () => confirming?.(true));
$('confirm').addEventListener('click', (e) => { if (e.target === $('confirm')) confirming?.(false); });
// while the box is up it owns the keyboard: ↵ deletes, esc cancels
document.addEventListener('keydown', (e) => {
  if (!confirming) return;
  e.preventDefault();
  e.stopPropagation();
  if (e.key === 'Enter') confirming(true);
  else if (e.key === 'Escape') confirming(false);
}, true);

async function deleteNote(note) {
  if (!note || confirming) return false;
  const ok = await confirmDelete(note);
  if (!ok) return false;
  if (note === current) { clearTimeout(saveTimer); current = null; }
  notes = notes.filter((n) => n !== note);
  await tiny.api.call('remove', { id: note.id });
  return true;
}

async function deleteCurrent() {
  if (await deleteNote(current)) showList();
  else $('editor').focus();
}

async function deleteSelected() {
  const keep = sel;
  if (await deleteNote(shown[sel])) {
    filter();
    moveSel(Math.min(keep, shown.length - 1));
  }
  $('q').focus();
}

$('editor').addEventListener('input', scheduleSave);
$('editor').addEventListener('keydown', async (e) => {
  if (e.key === 'Escape') { e.preventDefault(); await closeNote(); showList(); }
  else if (e.key === 'Backspace' && e.metaKey && e.shiftKey) { e.preventDefault(); deleteCurrent(); }
});
$('back').addEventListener('click', async () => { await closeNote(); showList(); });
$('del').addEventListener('click', deleteCurrent);

// ---------- settings ----------

const SYMBOLS = { ctrl: '⌃', alt: '⌥', shift: '⇧', cmd: '⌘' };
function prettyCombo(combo) {
  const parts = combo.split('+');
  const key = parts.pop();
  const mods = ['ctrl', 'alt', 'shift', 'cmd'].filter((m) => parts.includes(m)).map((m) => SYMBOLS[m]);
  const k = key === 'space' ? 'Space' : key.length === 1 ? key.toUpperCase() : key.toUpperCase();
  return mods.join('') + k;
}

let hotkey = null, defaultHotkey = null, recording = false;

async function showSettings() {
  await closeNote();
  view = 'settings';
  $('listView').hidden = true;
  $('editorView').hidden = true;
  $('settingsView').hidden = false;
  const hk = await tiny.api.call('getHotkey');
  hotkey = hk.combo; defaultHotkey = hk.default;
  stopRecording();
  const login = await tiny.app.launchAtLogin.get().catch(() => 'unsupported');
  $('login').checked = login === 'enabled';
  $('login').disabled = login === 'unsupported';
  $('loginHint').textContent = login === 'unsupported' ? 'Available in the built app (not in tinyjs dev).'
    : login === 'requires-approval' ? 'Allow NoteHero in System Settings › Login Items.' : '';
}

function stopRecording() {
  recording = false;
  $('recorder').classList.remove('recording');
  $('recorder').textContent = prettyCombo(hotkey);
  $('recHint').textContent = 'Click, then press a new key combination. It must include ⌘, ⌃ or ⌥.';
}

async function setHotkey(combo) {
  ({ combo: hotkey } = await tiny.api.call('setHotkey', { combo }));
  stopRecording();
}

$('recorder').addEventListener('click', () => {
  recording = true;
  $('recorder').classList.add('recording');
  $('recorder').textContent = 'Press shortcut…';
  $('recHint').textContent = 'Esc to cancel.';
});
// WebKit never focuses a clicked <button>, so the recorder can't hear keys
// itself — listen on the whole document (capture phase, ahead of the ⌘, / ⌘N
// shortcuts) while it's armed.
document.addEventListener('keydown', (e) => {
  if (!recording) return;
  e.preventDefault();
  e.stopPropagation();
  if (e.key === 'Escape') return stopRecording();
  let key = null, m;
  if ((m = /^Key([A-Z])$/.exec(e.code))) key = m[1].toLowerCase();
  else if ((m = /^Digit(\d)$/.exec(e.code))) key = m[1];
  else if (/^F\d{1,2}$/.test(e.code)) key = e.code.toLowerCase();
  else if (e.code === 'Space') key = 'space';
  if (!key) return;   // a bare modifier so far — keep waiting
  if (!(e.metaKey || e.ctrlKey || e.altKey)) {
    $('recHint').textContent = 'Add ⌘, ⌃ or ⌥ to that key.';
    return;
  }
  const mods = [e.ctrlKey && 'ctrl', e.altKey && 'alt', e.shiftKey && 'shift', e.metaKey && 'cmd'].filter(Boolean);
  setHotkey([...mods, key].join('+'));
}, true);
$('resetHotkey').addEventListener('click', () => setHotkey(defaultHotkey));
$('login').addEventListener('change', async (e) => {
  const r = await tiny.app.launchAtLogin.set(e.target.checked).catch(() => 'unsupported');
  if (r === 'requires-approval') $('loginHint').textContent = 'Allow NoteHero in System Settings › Login Items.';
});
$('quit').addEventListener('click', () => tiny.quit());
// clicking anywhere but the recorder cancels a recording in progress
document.addEventListener('mousedown', (e) => {
  if (recording && e.target !== $('recorder')) stopRecording();
});

// ---------- about ----------

const showAbout = (show) => { $('about').hidden = !show; };
$('aboutBtn').addEventListener('click', () => showAbout(true));
$('aboutClose').addEventListener('click', () => showAbout(false));
$('about').addEventListener('click', (e) => {
  if (e.target === $('about')) showAbout(false);
  const a = e.target.closest('a.ext');
  if (a) { e.preventDefault(); tiny.app.shell.open(a.dataset.url); }
});

// 'system' | 'light' | 'dark' — system leaves <html> unmarked so the CSS
// follows prefers-color-scheme (and the native vibrancy shows through)
function applyTheme(theme) {
  if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;
  else delete document.documentElement.dataset.theme;
  for (const b of $('theme').children)
    b.setAttribute('aria-checked', String(b.dataset.theme === (theme || 'system')));
}
$('theme').addEventListener('click', (e) => {
  const theme = e.target.closest('button')?.dataset.theme;
  if (!theme) return;
  applyTheme(theme);
  tiny.store.set('theme', theme);
});
$('settingsBack').addEventListener('click', () => showList());

// ---------- global keys & backend events ----------

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && !$('about').hidden) {
    e.preventDefault(); e.stopPropagation(); showAbout(false);
  }
}, true);
document.addEventListener('keydown', (e) => {
  if (e.metaKey && e.key === ',') { e.preventDefault(); showSettings(); }
  else if (e.metaKey && e.key === 'n') { e.preventDefault(); closeNote().then(() => createNote('')); }
  else if (e.key === 'Escape' && view === 'settings' && !recording) { e.preventDefault(); showList(); }
});

// tray click / global hotkey: always land in a fresh, focused search
tiny.api.on('summon', async () => {
  confirming?.(false);
  if (view === 'editor') await closeNote();
  showList({ reset: true });
});
tiny.api.on('open-settings', showSettings);
tiny.api.on('about', async () => { await showSettings(); showAbout(true); });

(async () => {
  applyTheme(await tiny.store.get('theme'));
  const { version } = await tiny.app.info();
  $('version').textContent = 'v' + version;
  $('aboutVersion').textContent = 'Version ' + version;
  notes = await tiny.api.call('list');
  showList();
})();
