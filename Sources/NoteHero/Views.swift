// The popover: search list, editor, settings, and the delete / about boxes.
import SwiftUI

private let line = Color(nsColor: .separatorColor)
private let field = Color.primary.opacity(0.06)
private let hover = Color.primary.opacity(0.05)
private let danger = Color(nsColor: .systemRed)

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            switch model.screen {
            case .list: ListScreen(model: model)
            case .editor: EditorScreen(model: model)
            case .settings: SettingsScreen(model: model)
            }
            if let title = model.confirmTitle {
                Overlay(dismiss: { model.answerConfirm(false) }) { ConfirmBox(model: model, title: title) }
            } else if model.showAbout {
                Overlay(dismiss: { model.showAbout = false }) { AboutBox(model: model) }
            }
        }
        .font(.system(size: 13))
        .frame(minWidth: 320, minHeight: 360)
    }
}

// MARK: - list

private struct ListScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                SearchField(model: model)
                IconButton(symbol: "gearshape.fill", help: "Settings (⌘,)") { model.showSettings() }
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 12))
            Divider()

            if model.shown.isEmpty {
                EmptyState(query: model.query.trimmingCharacters(in: .whitespaces))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.shown.enumerated()), id: \.element.id) { i, note in
                                NoteRow(note: note, terms: model.terms, selected: i == model.sel)
                                    .onTapGesture { model.openNote(note) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.sel) { _, sel in
                        if model.shown.indices.contains(sel) { proxy.scrollTo(model.shown[sel].id) }
                    }
                }
            }

            Footer {
                Hint(keys: ["↑", "↓"], "select")
                Hint(keys: ["↵"], "open")
                Hint(keys: ["⌘↵"], "new")
                Hint(keys: ["⌘⇧⌫"], "delete")
                Hint(keys: ["esc"], "close")
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let terms: [String]
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 10) {
                Text(highlight(titleOf(note.body), terms, selected: selected))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(fmtDate(note.updated))
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary)
            }
            let snippet = snippetOf(note.body, terms)
            Text(highlight(snippet.isEmpty ? " " : snippet, terms, selected: selected))
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.white.opacity(0.8) : .secondary)
                .lineLimit(1)
        }
        .foregroundStyle(selected ? Color.white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(selected ? Color.accentColor : hovering ? hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// `text` with every occurrence of any term marked.
private func highlight(_ text: String, _ terms: [String], selected: Bool) -> AttributedString {
    var s = AttributedString(text)
    let mark = selected ? Color.white.opacity(0.28) : Color.yellow.opacity(0.45)
    for t in terms {
        var from = text.startIndex
        while let r = text.range(of: t, options: .caseInsensitive, range: from..<text.endIndex) {
            if let ar = Range(r, in: s) { s[ar].backgroundColor = mark }
            from = r.upperBound
        }
    }
    return s
}

private struct EmptyState: View {
    let query: String

    var body: some View {
        var s = AttributedString(query.isEmpty ? "No notes yet. Type a title and press " : "No notes match. Press ")
        var enter = AttributedString("↵")
        enter.foregroundColor = .primary
        enter.font = .system(size: 13, weight: .semibold)
        s += enter
        s += AttributedString(query.isEmpty ? "." : " to create “\(query)”.")
        return Text(s)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(EdgeInsets(top: 28, leading: 20, bottom: 20, trailing: 20))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - editor

private struct EditorScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let note = model.current {
                    Text("Edited " + fmtDate(note.updated))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    LinkButton("‹ Notes") { model.closeNote(); model.showList() }
                    Spacer()
                    LinkButton("Delete", color: danger) { model.deleteCurrent() }
                        .help("Delete (⌘⇧⌫)")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            NoteEditor(model: model)
            Footer {
                Hint(keys: ["esc"], "back to notes")
                Hint(keys: ["⌘⇧⌫"], "delete")
                Spacer()
                Text(model.savedLabel)
            }
        }
    }
}

// MARK: - settings

private struct SettingsScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { model.showList() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(field))
                }
                .buttonStyle(.plain)
                .help("Close (esc)")
            }
            .padding(EdgeInsets(top: 12, leading: 18, bottom: 10, trailing: 12))
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Global shortcut")
                    Button { model.recording ? model.stopRecording() : model.startRecording() } label: {
                        Text(model.recording ? "Press shortcut…" : KeyCombo.pretty(model.hotkey))
                            .font(.system(size: 15))
                            .tracking(1)
                            .frame(minWidth: 200)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(field))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(model.recording ? Color.accentColor : line))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text(model.recHint).font(.system(size: 11)).foregroundStyle(.secondary)
                    LinkButton("Reset to default") { model.setHotkey(Prefs.defaultHotkey) }

                    Label("Appearance")
                    Picker("Appearance", selection: $model.theme) {
                        Text("System").tag(Theme.system)
                        Text("Light").tag(Theme.light)
                        Text("Dark").tag(Theme.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()

                    Label("Editor font")
                    FontSettings(font: $model.font)

                    Toggle("Launch at login", isOn: Binding(
                        get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                        set: { model.setLaunchAtLogin($0) }))
                        .disabled(model.loginStatus == .unsupported)
                        .padding(.top, 18)
                    if let error = model.loginError {
                        Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    switch model.loginStatus {
                    case .unsupported:
                        Text("Available when NoteHero runs from its app bundle.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    case .requiresApproval:
                        Text("Allow NoteHero in System Settings › Login Items.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }

            LinkButton("Quit NoteHero", color: danger) { NSApp.terminate(nil) }
                .padding(.bottom, 12)
            Footer(spacing: 4) {
                Spacer()
                Text("v\(model.version) ·")
                LinkButton("About") { model.showAbout = true }.font(.system(size: 11))
                Spacer()
            }
        }
    }

    private func Label(_ s: String) -> some View {
        Text(s).fontWeight(.semibold).padding(.top, 8)
    }
}

private struct FontSettings: View {
    @Binding var font: EditorFont

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("Font", selection: $font.family) {
                    ForEach(EditorFont.families, id: \.group) { g in
                        Section(g.group) {
                            ForEach(g.items, id: \.id) { Text($0.label).tag($0.id) }
                        }
                    }
                    Divider()
                    Text("Other…").tag("custom")
                }
                .labelsHidden()
                .fixedSize()
                if font.family == "custom" {
                    TextField("Font name, e.g. JetBrains Mono", text: $font.custom)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 12) {
                Picker("Size", selection: $font.size) {
                    ForEach(EditorFont.sizes, id: \.self) { Text("\(Int($0))").tag($0) }
                }
                .fixedSize()
                Picker("Line height", selection: $font.lineHeight) {
                    ForEach(EditorFont.lineHeights, id: \.self) {
                        Text($0.formatted(.number.precision(.fractionLength(1...2)))).tag($0)
                    }
                }
                .fixedSize()
            }
            .foregroundStyle(.secondary)
            Text("The quick brown fox 0O 1lI {}[] => !=")
                .font(Font(font.nsFont))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(field))
        }
    }
}

// MARK: - overlays

private struct Overlay<Content: View>: View {
    let dismiss: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).onTapGesture(perform: dismiss)
            content
                .frame(width: 280)
                .padding(EdgeInsets(top: 24, leading: 20, bottom: 18, trailing: 20))
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(line))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
        }
    }
}

private struct ConfirmBox: View {
    @ObservedObject var model: AppModel
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.system(size: 15, weight: .bold)).multilineTextAlignment(.center)
            Text("This can't be undone.").foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { model.answerConfirm(false) } label: { BoxLabel("Cancel", key: "esc") }
                    .buttonStyle(.plain)
                Button { model.answerConfirm(true) } label: { BoxLabel("Delete", key: "↵", danger: true) }
                    .buttonStyle(.plain)
            }
        }
    }
}

private struct AboutBox: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .padding(.top, -6)
            Text("NoteHero").font(.system(size: 15, weight: .bold)).padding(.top, 10)
            Text("Version \(model.version)").foregroundStyle(.secondary).padding(.top, 2)
            Text("Quick notes from your menu bar. Search, pick, or just start typing.")
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            HStack(spacing: 4) {
                Text("Made by")
                LinkButton("dondo.dev") { NSWorkspace.shared.open(URL(string: "https://dondo.dev")!) }
            }
            .padding(.vertical, 12)
            Button { model.showAbout = false } label: { BoxLabel("Close") }
                .buttonStyle(.plain)
        }
    }
}

// MARK: - bits

private struct BoxLabel: View {
    let title: String
    var key: String?
    var danger = false

    init(_ title: String, key: String? = nil, danger: Bool = false) {
        self.title = title
        self.key = key
        self.danger = danger
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let key { Kbd(key, onColor: danger) }
        }
        .foregroundStyle(danger ? Color.white : .primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(danger ? NoteHero.danger : field))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(danger ? .clear : line))
        .contentShape(Rectangle())
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

private struct LinkButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, color: Color = .accentColor, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).foregroundStyle(color).underline(hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct Footer<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: spacing) { content }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct Hint: View {
    let keys: [String]
    let label: String

    init(keys: [String], _ label: String) {
        self.keys = keys
        self.label = label
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { Kbd($0) }
            Text(label)
        }
    }
}

private struct Kbd: View {
    let key: String
    var onColor = false

    init(_ key: String, onColor: Bool = false) {
        self.key = key
        self.onColor = onColor
    }

    var body: some View {
        Text(key)
            .font(.system(size: 10))
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(onColor ? Color.white.opacity(0.25) : field))
    }
}
