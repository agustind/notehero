// The global shortcut, registered with Carbon (no Accessibility permission
// needed). Combos are strings like "ctrl+alt+n", the format the tinyjs builds
// stored, naming physical keys on an ANSI layout.
import AppKit
import Carbon.HIToolbox

enum KeyCombo {
    static let keyCodes: [String: Int] = {
        var m: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
            "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
            "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
            "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
            "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "space": kVK_Space,
        ]
        let fkeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (i, code) in fkeys.enumerated() { m["f\(i + 1)"] = code }
        return m
    }()
    static let keyNames = Dictionary(uniqueKeysWithValues: keyCodes.map { ($1, $0) })

    /// The combo for a key press, or nil while only modifiers are down or
    /// the key isn't one a shortcut can use.
    static func from(_ e: NSEvent) -> String? {
        guard let key = keyNames[Int(e.keyCode)] else { return nil }
        let f = e.modifierFlags
        let mods = [f.contains(.control) ? "ctrl" : nil, f.contains(.option) ? "alt" : nil,
                    f.contains(.shift) ? "shift" : nil, f.contains(.command) ? "cmd" : nil]
        return (mods.compactMap { $0 } + [key]).joined(separator: "+")
    }

    static func pretty(_ combo: String) -> String {
        var parts = combo.split(separator: "+").map(String.init)
        let key = parts.popLast() ?? ""
        let symbols = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"]
        let mods = ["ctrl", "alt", "shift", "cmd"].filter(parts.contains).compactMap { symbols[$0] }
        return mods.joined() + (key == "space" ? "Space" : key.uppercased())
    }

    fileprivate static func carbon(_ combo: String) -> (key: UInt32, mods: UInt32)? {
        var parts = combo.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.popLast(), let code = keyCodes[key] else { return nil }
        var mods = 0
        for p in parts {
            switch p {
            case "ctrl", "control": mods |= controlKey
            case "alt", "option", "opt": mods |= optionKey
            case "shift": mods |= shiftKey
            case "cmd", "command", "meta": mods |= cmdKey
            default: return nil
            }
        }
        return (UInt32(code), UInt32(mods))
    }
}

final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            let me = Unmanaged<HotKey>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Replace the registered shortcut. Returns false if macOS refused it
    /// (another app may own that combo).
    @discardableResult
    func register(_ combo: String) -> Bool {
        unregister()
        guard let (key, mods) = KeyCombo.carbon(combo) else { return false }
        let id = EventHotKeyID(signature: OSType(0x4E_48_45_52) /* 'NHER' */, id: 1)
        return RegisterEventHotKey(key, mods, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
