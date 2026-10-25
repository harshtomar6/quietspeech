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
    private static let cKey: CGKeyCode = 0x08 // kVK_ANSI_C

    /// Non-standard pasteboard markers honoured by clipboard-history tools.
    /// `TransientType` means "do not record this in history";
    /// `ConcealedType` means "this is private, do not display it". Dictation is
    /// private, and we want neither recorded nor revealed, so we set both.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Copies the current selection without leaving it on the clipboard.
    /// Used when an app does not expose AXSelectedText (Chrome and many
    /// Electron editors). Returns nil when nothing changed, so a stray Cmd+C
    /// on an empty selection can't be mistaken for a transcript.
    static func copySelection(timeout: Duration = .milliseconds(150)) async -> String? {
        guard AXIsProcessTrusted() else { return nil }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems
        let before = pasteboard.changeCount

        guard postCommand(key: cKey) else { return nil }

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
            guard pasteboard.changeCount != before else { continue }
            let text = pasteboard.string(forType: .string)
            let writtenChangeCount = pasteboard.changeCount
            restore(previous, expecting: writtenChangeCount)
            return text
        }
        return nil
    }

    @discardableResult
    static func insert(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard AXIsProcessTrusted() else { return false }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.pasteboardItems

        write(text, to: pasteboard)
        let writtenChangeCount = pasteboard.changeCount

        guard postCommand(key: vKey) else { return false }

        // Give the target app a moment to consume the paste, then put the
        // user's own clipboard contents back.
        if let previous, !previous.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                // If anything else wrote the clipboard after us (another
                // dictation, a copy, a clipboard manager), leave it alone.
                // Restoring an old snapshot would silently overwrite it.
                restore(previous, expecting: writtenChangeCount)
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
    private static func restore(_ items: [NSPasteboardItem]?, expecting changeCount: Int) {
        let pasteboard = NSPasteboard.general

        // If anything else wrote the clipboard after us, leave it alone.
        guard pasteboard.changeCount == changeCount else { return }

        guard let items, !items.isEmpty else {
            pasteboard.clearContents()
            return
        }

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

        // A lazy/promised provider can defeat every data(forType:) call. Do
        // not fall back to the original items: they are still associated with
        // a pasteboard, and AppKit raises "already associated with another
        // pasteboard" — an uncaught exception that kills the app. Leaving the
        // (transient) dictation on the clipboard is the safe outcome.
        guard !copies.isEmpty else { return }

        pasteboard.clearContents()
        pasteboard.writeObjects(copies)
    }

    private static func postCommand(key: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
