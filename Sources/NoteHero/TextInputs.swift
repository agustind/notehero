// AppKit text inputs, so focus, selection and the editor's font and line
// height are fully under our control.
import AppKit
import SwiftUI

struct SearchField: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.isBezeled = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 17)
        f.placeholderString = "Search or create a note…"
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.delegate = context.coordinator
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        if f.stringValue != model.query { f.stringValue = model.query }
        if context.coordinator.focus != model.searchFocus {
            context.coordinator.focus = model.searchFocus
            DispatchQueue.main.async {
                f.window?.makeFirstResponder(f)
                f.currentEditor()?.selectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: AppModel
        var focus = -1
        init(model: AppModel) { self.model = model }

        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            MainActor.assumeIsolated { model.setQuery(f.stringValue) }
        }
    }
}

struct NoteEditor: NSViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let tv = NoteTextView()
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        tv.drawsBackground = false
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.textContainerInset = NSSize(width: 11, height: 14)
        tv.delegate = context.coordinator
        tv.textStorage?.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        let c = context.coordinator
        if c.font != model.font {
            c.font = model.font
            applyFont(model.font, to: tv)
        }
        if c.load != model.editorLoad {
            c.load = model.editorLoad
            tv.string = model.editorText
            applyFont(model.font, to: tv)
            tv.undoManager?.removeAllActions()
            let atEnd = model.editorCaretAtEnd
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: atEnd ? (tv.string as NSString).length : 0, length: 0))
                if atEnd { tv.scrollToEndOfDocument(nil) } else { tv.scrollToBeginningOfDocument(nil) }
            }
        } else if c.focus != model.editorFocus {
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        c.focus = model.editorFocus
    }

    private func applyFont(_ f: EditorFont, to tv: NSTextView) {
        let font = f.nsFont
        // CSS-style line height: every line is size × lineHeight tall, with the
        // text centred in it
        let line = (CGFloat(f.size) * CGFloat(f.lineHeight)).rounded()
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = line
        para.maximumLineHeight = line
        let natural = font.ascender - font.descender
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: para,
            .baselineOffset: max(0, (line - natural) / 2),
            .foregroundColor: NSColor.labelColor,
        ]
        tv.typingAttributes = attrs
        guard let ts = tv.textStorage else { return }
        ts.setAttributes(attrs, range: NSRange(location: 0, length: ts.length))
        styleChecks(ts, in: NSRange(location: 0, length: ts.length), font: f)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        let model: AppModel
        var load = -1, focus = -1
        var font: EditorFont?
        init(model: AppModel) { self.model = model }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            MainActor.assumeIsolated { model.editorChanged(tv.string) }
        }

        /// ".-" at the start of a line becomes an unchecked checkbox.
        func textView(_ tv: NSTextView, shouldChangeTextIn r: NSRange, replacementString s: String?) -> Bool {
            guard s == "-", r.length == 0, r.location > 0, !tv.hasMarkedText() else { return true }
            let text = tv.string as NSString
            let dot = r.location - 1
            guard text.character(at: dot) == 0x2E else { return true }
            let start = text.lineRange(for: NSRange(location: dot, length: 0)).location
            guard text.substring(with: NSRange(location: start, length: dot - start))
                .allSatisfy({ $0 == " " || $0 == "\t" }) else { return true }
            tv.insertText("\(Checkbox.open) ", replacementRange: NSRange(location: dot, length: 1))
            return false
        }

        /// ↵ on a checkbox line starts another one; on an empty one, removes it.
        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            guard sel == #selector(NSResponder.insertNewline(_:)), tv.selectedRange().length == 0
            else { return false }
            let text = tv.string as NSString
            let caret = tv.selectedRange().location
            let line = lineContent(text, at: caret)
            guard let box = checkboxPrefix(text, line), caret >= box.end else { return false }
            let rest = text.substring(with: NSRange(location: box.end, length: NSMaxRange(line) - box.end))
            if rest.allSatisfy(\.isWhitespace) {
                tv.insertText("", replacementRange: NSRange(location: box.indent.location, length: box.end - box.indent.location))
            } else {
                tv.insertText("\n" + text.substring(with: box.indent) + "\(Checkbox.open) ", replacementRange: tv.selectedRange())
            }
            return true
        }

        func textStorage(_ ts: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions,
                         range: NSRange, changeInLength: Int) {
            guard mask.contains(.editedCharacters), let font else { return }
            styleChecks(ts, in: (ts.string as NSString).paragraphRange(for: range), font: font)
        }
    }
}

// MARK: - checkboxes

enum Checkbox {
    static let open = "☐", done = "☑"
    static let openChar: unichar = 0x2610, doneChar: unichar = 0x2611
}

/// The line containing `i`, without its line break.
private func lineContent(_ text: NSString, at i: Int) -> NSRange {
    var start = 0, end = 0
    text.getLineStart(&start, end: nil, contentsEnd: &end, for: NSRange(location: i, length: 0))
    return NSRange(location: start, length: end - start)
}

/// A line that starts (after any indent) with a checkbox: the indent, the box's index, and where
/// the item's text begins.
private func checkboxPrefix(_ text: NSString, _ line: NSRange) -> (indent: NSRange, box: Int, end: Int)? {
    var i = line.location
    while i < NSMaxRange(line), [0x20, 0x09].contains(text.character(at: i)) { i += 1 }
    guard i < NSMaxRange(line), [Checkbox.openChar, Checkbox.doneChar].contains(text.character(at: i))
    else { return nil }
    let end = i + 1 < NSMaxRange(line) && text.character(at: i + 1) == 0x20 ? i + 2 : i + 1
    return (NSRange(location: line.location, length: i - line.location), i, end)
}

/// Draws checkboxes in a symbol font (editor fonts lack them, and ☑ would fall back to the emoji),
/// and dims and strikes through the text of checked items in `range` (whole lines).
private func styleChecks(_ ts: NSTextStorage, in range: NSRange, font f: EditorFont) {
    let text = ts.string as NSString
    let boxFont = NSFont(name: "Apple Symbols", size: (CGFloat(f.size) * 1.3).rounded()) ?? f.nsFont
    ts.removeAttribute(.strikethroughStyle, range: range)
    ts.addAttributes([.font: f.nsFont, .foregroundColor: NSColor.labelColor], range: range)
    text.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
        guard let box = checkboxPrefix(text, line) else { return }
        ts.addAttribute(.font, value: boxFont, range: NSRange(location: box.box, length: 1))
        guard text.character(at: box.box) == Checkbox.doneChar else { return }
        ts.addAttributes([
            .foregroundColor: NSColor.secondaryLabelColor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ], range: NSRange(location: box.end, length: NSMaxRange(line) - box.end))
    }
}

/// The note editor's text view: clicking a checkbox toggles it.
final class NoteTextView: NSTextView {
    override func mouseDown(with e: NSEvent) {
        if let i = checkbox(at: e) { toggleCheckbox(at: i) } else { super.mouseDown(with: e) }
    }

    private func checkbox(at e: NSEvent) -> Int? {
        guard let window else { return nil }
        let text = string as NSString
        let i = characterIndexForInsertion(at: convert(e.locationInWindow, from: nil))
        let p = window.convertPoint(toScreen: e.locationInWindow)
        for j in [i, i - 1] where j >= 0 && j < text.length
            && [Checkbox.openChar, Checkbox.doneChar].contains(text.character(at: j)) {
            let r = firstRect(forCharacterRange: NSRange(location: j, length: 1), actualRange: nil)
            if r.insetBy(dx: -2, dy: -2).contains(p) { return j }
        }
        return nil
    }

    private func toggleCheckbox(at i: Int) {
        let r = NSRange(location: i, length: 1)
        let new = (string as NSString).character(at: i) == Checkbox.openChar ? Checkbox.done : Checkbox.open
        guard shouldChangeText(in: r, replacementString: new) else { return }
        textStorage?.replaceCharacters(in: r, with: new)
        didChangeText()
    }
}
