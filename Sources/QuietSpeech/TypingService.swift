import AppKit
import ApplicationServices
import os

/// Types text into the frontmost app by synthesizing Unicode key events.
/// Nothing touches the pasteboard, so clipboard managers never see it.
///
/// This is the middle tier of a three-step insertion strategy:
///
///   1. `AXInsertService` — a real AX write, instantly and atomically.
///   2. this — synthetic key events, for apps that don't accept an AX write
///      (terminals, Electron editors, many web fields).
///   3. `PasteService` — clipboard + ⌘V, a last resort because it pollutes
///      clipboard history in managers that ignore the nspasteboard.org
///      convention (FlyCut 1.9.6 ignores it entirely).
///
/// Events are posted one character at a time rather than as one big string.
/// A single event carrying the whole string is faster, but several apps only
/// read the first character of such an event; per-character matches what
/// AppleScript's `keystroke` does and is the more compatible shape.
enum TypingService {

    private static let log = Logger(subsystem: "dev.harsh.quietspeech", category: "insert")

    /// Beyond this, an event-per-character storm is worse than borrowing the
    /// clipboard for a moment.
    private static let maxCharacters = 4000

    @discardableResult
    static func type(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        // Posting events is gated on Accessibility, same as the rest.
        guard AXIsProcessTrusted() else {
            log.debug("typing: no Accessibility permission")
            return false
        }
        guard text.count <= maxCharacters else {
            log.notice("typing: refusing \(text.count) chars (limit \(maxCharacters))")
            return false
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            log.debug("typing: could not create event source")
            return false
        }

        var posted = 0
        for character in text {
            var units = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            // Virtual key 0 is "A". Without clearing the flags the events pick
            // up whatever modifier the session thinks is held, and an Electron
            // editor reads Cmd+A (select all) instead of the character.
            down.flags = []
            up.flags = []
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            posted += 1
        }

        guard posted == text.count else {
            log.debug("typing: only posted \(posted)/\(text.count) characters")
            return false
        }
        log.notice("typing: posted \(posted) characters")
        return true
    }
}
