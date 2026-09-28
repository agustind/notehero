// Everything the popover shows, and what the keyboard does to it.
import AppKit
import ServiceManagement

enum Screen { case list, editor, settings }

enum LoginStatus { case enabled, disabled, requiresApproval, unsupported }

@MainActor
final class AppModel: ObservableObject {
    private let db: NotesDB

    private(set) var notes: [Note] = []                 // every note, newest first
    @Published private(set) var shown: [Note] = []      // notes currently in the list
    @Published private(set) var terms: [String] = []    // search terms behind `shown`
    @Published var sel = 0                              // index into `shown`
    @Published var query = ""
    @Published private(set) var screen: Screen = .list

    // editor
    @Published private(set) var current: Note?          // note open in the editor
    private(set) var editorText = ""
    private(set) var editorCaretAtEnd = false
    @Published private(set) var savedLabel = ""
    private var saveTimer: Timer?

    // bumped to move focus into (and reset) the search field / editor
    @Published private(set) var searchFocus = 0
    @Published private(set) var editorLoad = 0
    @Published private(set) var editorFocus = 0

    // overlays
    @Published private(set) var confirmTitle: String?  // set while a delete awaits confirmation
    private var confirming: ((Bool) -> Void)?
    @Published var showAbout = false

    // settings
    @Published private(set) var hotkey = Prefs.hotkey
    @Published private(set) var recording = false
    @Published private(set) var recHint = ""
    @Published var theme = Prefs.theme {
        didSet { Prefs.theme = theme; NSApp.appearance = theme.appearance }
    }
    @Published var font = Prefs.font {
        didSet { Prefs.font = font }
    }
    @Published private(set) var loginStatus = LoginStatus.unsupported
    @Published private(set) var loginError: String?

    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    /// Put the popover away and hand focus back to the previous app.
    var hide: () -> Void = {}
    /// Register a new global shortcut; false if macOS refused it.
    var registerHotkey: (String) -> Bool = { _ in true }

    init(db: NotesDB) {
        self.db = db
        notes = db.list()
        NSApp.appearance = theme.appearance
        stopRecording()
        showList()
    }

    // MARK: - list

    func setQuery(_ q: String) {
        query = q
        filter()
    }

    func filter() {
        terms = termsOf(query)
        if terms.isEmpty {
            shown = notes
        } else {
            let terms = self.terms
            shown = notes
                .map { (note: $0, lower: $0.body.lowercased(), title: titleOf($0.body).lowercased()) }
                .filter { x in terms.allSatisfy { x.lower.contains($0) } }
                .sorted { a, b in
                    let ta = terms.allSatisfy { a.title.contains($0) }, tb = terms.allSatisfy { b.title.contains($0) }
                    return ta != tb ? ta : a.note.updated > b.note.updated
                }
                .map(\.note)
        }
        sel = 0
    }

    func moveSel(_ delta: Int) {
        guard !shown.isEmpty else { return }
        sel = max(0, min(shown.count - 1, sel + delta))
    }

    func showList(reset: Bool = false) {
        if recording { stopRecording() }
        showAbout = false
        screen = .list
        if reset { query = "" }
        filter()
        searchFocus += 1
    }

    // MARK: - editor

    func createNote(_ title: String) {
        guard let note = db.create(body: title.isEmpty ? "" : title + "\n\n") else { return }
        notes.insert(note, at: 0)
        openNote(note, caretAtEnd: true)
    }

    /// Opens at the top; a note just created puts the cursor below its title.
    func openNote(_ note: Note?, caretAtEnd: Bool = false) {
        guard let note else { return }
        current = note
        editorCaretAtEnd = caretAtEnd
        editorText = note.body
        savedLabel = ""
        screen = .editor
        editorLoad += 1
    }

    func editorChanged(_ text: String) {
        editorText = text
        saveTimer?.invalidate()
        savedLabel = "Editing…"
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushSave() }
        }
    }

    private func flushSave() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard var note = current, editorText != note.body else { return }
        note.body = editorText
        note.updated = db.save(id: note.id, body: note.body)
        current = note
        // most recently edited floats to the top
        notes = [note] + notes.filter { $0.id != note.id }
        if screen == .editor { savedLabel = "Saved" }
    }

    /// Leave the editor; a note left blank is thrown away.
    func closeNote() {
        guard let note = current else { return }
        if editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveTimer?.invalidate()
            current = nil
            notes.removeAll { $0.id == note.id }
            db.remove(id: note.id)
        } else {
            flushSave()
            current = nil
        }
    }

    // MARK: - delete (with confirmation)

    private func confirmDelete(_ note: Note, then done: @escaping (Bool) -> Void) {
        confirmTitle = "Delete “\(titleOf(note.body))”?"
        confirming = { [weak self] ok in
            self?.confirming = nil
            self?.confirmTitle = nil
            done(ok)
        }
    }

    func answerConfirm(_ ok: Bool) { confirming?(ok) }

    private func deleteNote(_ note: Note?, then done: @escaping (Bool) -> Void) {
        guard let note, confirming == nil else { return done(false) }
        confirmDelete(note) { [weak self] ok in
            guard let self, ok else { return done(false) }
            if note.id == current?.id { saveTimer?.invalidate(); current = nil }
            notes.removeAll { $0.id == note.id }
            db.remove(id: note.id)
            done(true)
        }
    }

    func deleteCurrent() {
        deleteNote(current) { [weak self] ok in
            if ok { self?.showList() } else { self?.editorFocus += 1 }
        }
    }

    func deleteSelected() {
        let keep = sel
        deleteNote(shown.indices.contains(sel) ? shown[sel] : nil) { [weak self] ok in
            guard let self else { return }
            if ok {
                filter()
                sel = max(0, min(keep, shown.count - 1))
            }
            searchFocus += 1
        }
    }

    // MARK: - settings

    func showSettings() {
        closeNote()
        screen = .settings
        stopRecording()
        refreshLogin()
    }

    func startRecording() {
        recording = true
        recHint = "Esc to cancel."
    }

    func stopRecording() {
        recording = false
        recHint = "Click, then press a new key combination. It must include ⌘, ⌃ or ⌥."
    }

    func setHotkey(_ combo: String) {
        let combo = combo.lowercased()
        if registerHotkey(combo) {
            hotkey = combo
            Prefs.hotkey = combo
            stopRecording()
        } else {
            _ = registerHotkey(hotkey)
            stopRecording()
            recHint = "\(KeyCombo.pretty(combo)) is taken by another app. Try another."
        }
    }

    private func refreshLogin() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { loginStatus = .unsupported; return }
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = .enabled
        case .requiresApproval: loginStatus = .requiresApproval
        default: loginStatus = .disabled
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        loginError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = error.localizedDescription
        }
        refreshLogin()
    }

    // MARK: - backend events

    /// Status item click / global hotkey: always land in a fresh, focused search.
    func summoned() {
        confirming?(false)
        if screen == .editor { closeNote() }
        showList(reset: true)
    }

    // MARK: - keyboard

    /// Handles a key press in the popover. Returns true when it was used.
    func handleKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = mods.contains(.command), shift = mods.contains(.shift), ctrl = mods.contains(.control)
        let chars = e.charactersIgnoringModifiers?.lowercased() ?? ""
        let key = Int(e.keyCode)
        let isEnter = key == 36 || key == 76, isEsc = key == 53, isDelete = key == 51

        // while the box is up it owns the keyboard: ↵ deletes, esc cancels
        if let confirming {
            if isEnter { confirming(true) } else if isEsc { confirming(false) }
            return true
        }
        if recording {
            if isEsc { stopRecording(); return true }
            guard let combo = KeyCombo.from(e) else { return true }   // a bare modifier so far
            if !(cmd || ctrl || mods.contains(.option)) {
                recHint = "Add ⌘, ⌃ or ⌥ to that key."
                return true
            }
            setHotkey(combo)
            return true
        }
        if showAbout && isEsc { showAbout = false; return true }

        // an input method is composing: let it have ↵ / esc / arrows
        if let tv = e.window?.firstResponder as? NSTextView, tv.hasMarkedText() { return false }

        switch screen {
        case .list:
            if key == 125 || (ctrl && chars == "n") { moveSel(1); return true }
            if key == 126 || (ctrl && chars == "p") { moveSel(-1); return true }
            if isDelete && cmd && shift { deleteSelected(); return true }
            if isEnter {
                if cmd || shown.isEmpty { createNote(query.trimmingCharacters(in: .whitespaces)) }
                else { openNote(shown[sel]) }
                return true
            }
            if isEsc {
                if !query.isEmpty { setQuery("") } else { hide() }
                return true
            }
        case .editor:
            if isEsc { closeNote(); showList(); return true }
            if isDelete && cmd && shift { deleteCurrent(); return true }
        case .settings:
            if isEsc { showList(); return true }
        }

        if cmd && !shift && chars == "," { showSettings(); return true }
        if cmd && !shift && chars == "n" { closeNote(); createNote(""); return true }
        return false
    }
}

// MARK: - helpers

func linesOf(_ body: String) -> [String] {
    body.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

func titleOf(_ body: String) -> String {
    guard let first = linesOf(body).first else { return "Untitled" }
    return first.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
}

func termsOf(_ q: String) -> [String] {
    q.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
}

/// The line under the title that best shows why this note matched.
func snippetOf(_ body: String, _ terms: [String]) -> String {
    let rest = Array(linesOf(body).dropFirst())
    if !terms.isEmpty, let hit = rest.first(where: { l in terms.contains { l.lowercased().contains($0) } }) {
        let first = terms.compactMap { hit.range(of: $0, options: .caseInsensitive)?.lowerBound }.min()
        if let first, hit.distance(from: hit.startIndex, to: first) > 30 {
            return "…" + hit[hit.index(first, offsetBy: -30)...]
        }
        return hit
    }
    return rest.joined(separator: "  ·  ")
}

func fmtDate(_ ms: Int64) -> String {
    let d = Date(timeIntervalSince1970: Double(ms) / 1000)
    let cal = Calendar.current
    if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
    if cal.component(.year, from: d) == cal.component(.year, from: Date()) {
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
    return d.formatted(.dateTime.month(.abbreviated).day().year())
}
