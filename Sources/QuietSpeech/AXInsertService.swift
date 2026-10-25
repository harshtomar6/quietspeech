import AppKit
import ApplicationServices
import os

/// Types text at the caret using the Accessibility API, avoiding the clipboard
/// entirely. Returns `false` when it declines to try, so the caller can fall
/// back to `PasteService`.
///
/// The contract is deliberately one-way: if the AX write reports success we
/// commit to it and never paste. An earlier version re-read the value
/// immediately afterwards and treated "unchanged" as failure — but apps apply
/// AX writes asynchronously, so that read-back is routinely stale. The result
/// was inserting via AX *and* pasting, i.e. doubled text. A stale read-back can
/// never cost us the transcript (we can't un-insert anyway); pasting is what
/// causes damage, so verification is now advisory only — it logs, and can warn
/// the user, but never triggers a paste.
enum AXInsertService {

    private static let log = Logger(subsystem: "dev.harsh.quietspeech", category: "insert")

    /// Don't pull enormous documents over the AX bridge just to sanity-check.
    private static let maxReadableValueLength = 100_000

    /// Called on the main queue when a later read-back suggests the write didn't
    /// land, so the UI can nudge the user toward the Copy button.
    static var onUnverifiedInsert: (() -> Void)?

    @discardableResult
    static func insert(_ text: String) -> Bool {
        guard !text.isEmpty, AXIsProcessTrusted() else { return false }
        guard let element = focusedElement() else {
            log.debug("ax insert: no focused element")
            return false
        }

        // We need the current value to sanity-check the write afterwards.
        guard let before = stringAttribute(kAXValueAttribute as CFString, of: element) else {
            log.debug("ax insert: element exposes no readable AXValue")
            return false
        }
        guard before.count <= maxReadableValueLength else {
            log.debug("ax insert: value too large (\(before.count) chars)")
            return false
        }

        // A settable selection is the correct insertion point — it splices at
        // the caret and replaces the selection, exactly like a real keypress.
        guard isSettable(kAXSelectedTextAttribute as CFString, element) else {
            log.debug("ax insert: AXSelectedText not settable (role=\(self.role(of: element), privacy: .public))")
            return false
        }

        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard status == .success else {
            log.debug("ax insert: set failed with AXError \(status.rawValue)")
            return false
        }

        log.notice("ax insert: ok, committed (\(before.count) chars before)")
        verifyLater(element: element, before: before)
        return true
    }

    /// Advisory only — logs, and warns the UI, but never causes a paste.
    private static func verifyLater(element: AXUIElement, before: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let after = stringAttribute(kAXValueAttribute as CFString, of: element) else {
                log.debug("ax insert: unverified (value no longer readable)")
                return
            }
            if after == before {
                log.notice("ax insert: value still unchanged 0.4s later — text may not have landed")
                onUnverifiedInsert?()
            } else {
                log.debug("ax insert: verified (\(before.count) -> \(after.count) chars)")
            }
        }
    }

    // MARK: - AX plumbing

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value else { return nil }
        return value as? String
    }

    private static func isSettable(_ attribute: CFString, _ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private static func role(of element: AXUIElement) -> String {
        stringAttribute(kAXRoleAttribute as CFString, of: element) ?? "unknown"
    }
}
