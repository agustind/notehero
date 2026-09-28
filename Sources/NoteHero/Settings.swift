// Where things live on disk, and the user's preferences (kept in UserDefaults).
import AppKit

enum Paths {
    static let bundleID = "io.github.agustind.notehero"
    // 0.1.0 shipped under this bundle id; its data folder is migrated on launch
    static let oldID = "com.agudondo.notehero"

    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    // NOTEHERO_DATA_DIR points a dev build at a scratch copy of the notes
    static let data = ProcessInfo.processInfo.environment["NOTEHERO_DATA_DIR"].map { URL(fileURLWithPath: $0) }
        ?? support.appendingPathComponent(bundleID)
    static let db = data.appendingPathComponent("notes.db")
    // settings file of the tinyjs builds (0.1.x), imported once
    static let legacyStore = data.appendingPathComponent("store.json")

    /// Copy notes and settings from the 0.1.0 data folder the first time this
    /// build runs. The old folder is left in place as a backup.
    static func migrate() {
        let fm = FileManager.default
        let old = support.appendingPathComponent(oldID)
        try? fm.createDirectory(at: data, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: db.path),
              fm.fileExists(atPath: old.appendingPathComponent("notes.db").path) else { return }
        for f in ["notes.db", "store.json"] {
            try? fm.copyItem(at: old.appendingPathComponent(f), to: data.appendingPathComponent(f))
        }
    }
}

enum Theme: String, CaseIterable {
    case system, light, dark

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct EditorFont: Equatable {
    var family = "sf-mono"
    var custom = ""
    var size: Double = 13
    var lineHeight: Double = 1.5

    static let sizes: [Double] = [10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24]
    static let lineHeights: [Double] = [1.2, 1.35, 1.5, 1.65, 1.8, 2]

    /// (id, label) in menu order, grouped
    static let families: [(group: String, items: [(id: String, label: String)])] = [
        ("Monospace", [("sf-mono", "SF Mono"), ("menlo", "Menlo"), ("monaco", "Monaco"), ("courier", "Courier New")]),
        ("Sans-serif", [("system", "San Francisco"), ("helvetica", "Helvetica Neue"), ("avenir", "Avenir Next")]),
        ("Serif", [("new-york", "New York"), ("georgia", "Georgia")]),
    ]
    static let knownFamilies = Set(families.flatMap { $0.items.map(\.id) })

    var nsFont: NSFont {
        let size = CGFloat(size)
        let mono = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        func named(_ name: String) -> NSFont? {
            NSFont(name: name, size: size)
                ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
        }
        switch family {
        case "sf-mono": return mono
        case "menlo": return named("Menlo") ?? mono
        case "monaco": return named("Monaco") ?? mono
        case "courier": return named("Courier New") ?? named("Courier") ?? mono
        case "system": return .systemFont(ofSize: size)
        case "helvetica": return named("Helvetica Neue") ?? .systemFont(ofSize: size)
        case "avenir": return named("Avenir Next") ?? .systemFont(ofSize: size)
        case "new-york":
            let d = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
            return d.flatMap { NSFont(descriptor: $0, size: size) } ?? named("Georgia") ?? mono
        case "georgia": return named("Georgia") ?? mono
        case "custom":
            let name = custom.trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? mono : named(name) ?? mono
        default: return mono
        }
    }
}

/// Preferences, backed by UserDefaults.
enum Prefs {
    static let defaultHotkey = "ctrl+alt+n"
    private static let d = UserDefaults.standard

    static var hotkey: String {
        get { d.string(forKey: "hotkey") ?? defaultHotkey }
        set { d.set(newValue, forKey: "hotkey") }
    }

    static var theme: Theme {
        get { Theme(rawValue: d.string(forKey: "theme") ?? "") ?? .system }
        set { d.set(newValue.rawValue, forKey: "theme") }
    }

    static var font: EditorFont {
        get {
            var f = EditorFont()
            if let v = d.string(forKey: "fontFamily"), EditorFont.knownFamilies.contains(v) || v == "custom" { f.family = v }
            if let v = d.string(forKey: "fontCustom") { f.custom = v }
            if d.object(forKey: "fontSize") != nil { f.size = d.double(forKey: "fontSize") }
            if d.object(forKey: "lineHeight") != nil { f.lineHeight = d.double(forKey: "lineHeight") }
            return f
        }
        set {
            d.set(newValue.family, forKey: "fontFamily")
            d.set(newValue.custom, forKey: "fontCustom")
            d.set(newValue.size, forKey: "fontSize")
            d.set(newValue.lineHeight, forKey: "lineHeight")
        }
    }

    /// Bring over the hotkey, theme and font from the tinyjs builds' store.json.
    static func importLegacyStore() {
        guard !d.bool(forKey: "importedLegacyStore") else { return }
        d.set(true, forKey: "importedLegacyStore")
        guard let data = try? Data(contentsOf: Paths.legacyStore),
              let store = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let v = store["hotkey"] as? String { hotkey = v }
        if let v = store["theme"] as? String, let t = Theme(rawValue: v) { theme = t }
        if let v = store["font"] as? [String: Any] {
            var f = EditorFont()
            if let x = v["family"] as? String { f.family = x }
            if let x = v["custom"] as? String { f.custom = x }
            if let x = v["size"] as? Double { f.size = x }
            if let x = v["lineHeight"] as? Double { f.lineHeight = x }
            font = f
        }
    }
}
