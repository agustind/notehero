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
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let tv = scroll.documentView as! NSTextView
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
        tv.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: tv.textStorage?.length ?? 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        var load = -1, focus = -1
        var font: EditorFont?
        init(model: AppModel) { self.model = model }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            MainActor.assumeIsolated { model.editorChanged(tv.string) }
        }
    }
}
