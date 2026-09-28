// NoteHero: a menu bar icon and a global shortcut summon a popover-style
// panel under the icon; notes live in SQLite.
import AppKit
import SwiftUI

/// Borderless, translucent, and able to take the keyboard.
final class PopoverPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        // follow the user onto whatever Space / fullscreen app they're in
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        minSize = NSSize(width: 320, height: 360)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var panel: PopoverPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey!
    private let menu = NSMenu()
    // Clicking the status item while the popover is open may first blur (and
    // hide) the panel, then deliver the click — remember when that happened
    // so the click doesn't immediately re-open it.
    private var lastBlurHide = Date.distantPast

    func applicationDidFinishLaunching(_ note: Notification) {
        Paths.migrate()
        Prefs.importLegacyStore()
        let db: NotesDB
        do { db = try NotesDB(path: Paths.db.path) } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }

        model = AppModel(db: db)
        model.hide = { NSApp.hide(nil) }
        hotKey = HotKey { [weak self] in self?.summon() }
        model.registerHotkey = { [weak self] in self?.hotKey.register($0) ?? false }
        hotKey.register(model.hotkey)

        buildMainMenu()
        buildPanel()
        buildStatusItem()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === panel else { return e }
            return model.handleKey(e) ? nil : e
        }
    }

    // MARK: - panel

    private func buildPanel() {
        panel = PopoverPanel(size: NSSize(width: 440, height: 520))
        panel.delegate = self
        panel.setFrameAutosaveName("NoteHero")

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true

        let host = NSHostingView(rootView: RootView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
    }

    private func summon() {
        if panel.isVisible && panel.isKeyWindow {
            NSApp.hide(nil)
            return
        }
        position()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.summoned()
    }

    /// Just under the menu bar icon, kept on screen.
    private func position() {
        let size = panel.frame.size
        guard let button = statusItem.button, let win = button.window, let screen = win.screen else {
            panel.center()
            return
        }
        let spot = win.convertToScreen(button.convert(button.bounds, to: nil))
        let vis = screen.visibleFrame
        let x = max(vis.minX + 8, min((spot.midX - size.width / 2).rounded(), vis.maxX - size.width - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: spot.minY - 4 - size.height))
    }

    // Behave like a popover: clicking anywhere else puts it away.
    func windowDidResignKey(_ note: Notification) {
        guard panel.isVisible else { return }
        lastBlurHide = Date()
        panel.orderOut(nil)
    }

    // MARK: - status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let button = statusItem.button!
        button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NoteHero")
        button.toolTip = "NoteHero"
        button.target = self
        button.action = #selector(statusClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        for (title, action) in [("Open NoteHero", #selector(openFromMenu)), ("Settings…", #selector(openSettings)),
                                ("About NoteHero", #selector(openAbout))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NoteHero", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }

    @objc private func statusClicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if Date().timeIntervalSince(lastBlurHide) < 0.4 { return }
        summon()
    }

    @objc private func openFromMenu() { summon() }
    @objc private func openSettings() { summon(); model.showSettings() }
    @objc private func openAbout() { summon(); model.showSettings(); model.showAbout = true }

    // MARK: - main menu

    /// Never shown (the app has no Dock icon), but it's what makes ⌘C, ⌘V,
    /// ⌘Z, ⌘A and ⌘Q work.
    private func buildMainMenu() {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: "Quit NoteHero", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "NoteHero", action: nil, keyEquivalent: "").submenu = app

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = main
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
