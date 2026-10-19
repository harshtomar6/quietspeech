import AppKit

/// Types text into whatever app is frontmost by putting it on the pasteboard
/// and synthesizing ⌘V. Requires Accessibility permission.
///
/// The clipboard is restored shortly afterwards so we don't clobber the user's
/// own copy buffer, and every write is flagged transient/concealed so clipboard
/// managers (Maccy, Raycast, Paste, Clipy, Alfred…) keep dictations out of their
/// history.
enum PasteService {

    private static let vKey: CGKeyCode = 0x09 // kVK_ANSI_V

    /// Non-standard pasteboard markers honoured by clipboard-history tools.
    /// `TransientType` means "do not record this in history";
    /// `ConcealedType` means "this is private, do not display it". Dictation is
    /// private, and we want neither recorded nor revealed, so we set both.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    @discardableResult
    static func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard AXIsProcessTrusted() else { return false }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems

        write(text, to: pasteboard)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        // Give the target app a moment to consume the paste, then put the
        // user's own clipboard contents back.
        if let previous, !previous.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                restore(previous)
            }
        }
        return true
    }

    /// Writes `text` as a transient, concealed pasteboard entry.
    private static func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // The markers carry no data; their mere presence in `types` is the signal.
        item.setData(Data(), forType: transientType)
        item.setData(Data(), forType: concealedType)

        pasteboard.writeObjects([item])
    }

    /// Reinstates the clipboard the user had before we borrowed it, re-flagging
    /// the contents as transient so restoring doesn't itself create a new
    /// history entry duplicating the user's earlier copy.
    private static func restore(_ items: [NSPasteboardItem]) {
        let pasteboard = NSPasteboard.general

        var copies: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            var copiedAnything = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    copiedAnything = true
                }
            }
            guard copiedAnything else { continue }
            copy.setData(Data(), forType: transientType)
            copies.append(copy)
        }

        pasteboard.clearContents()
        if copies.isEmpty {
            // A lazy/promised provider defeated the copy; restore untouched
            // rather than dropping the user's clipboard on the floor.
            pasteboard.writeObjects(items)
        } else {
            pasteboard.writeObjects(copies)
        }
    }
}
