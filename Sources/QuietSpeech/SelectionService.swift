import AppKit
import ApplicationServices
import os

enum SelectionSource {
    case accessibility
    case clipboard
}

struct SelectionSnapshot {
    let text: String
    /// The element that reported the selection. Usually the focused element,
    /// but browsers can expose a selection on a descendant of it.
    let element: AXUIElement?
    /// The focused element at the moment the selection was captured.
    let focus: AXUIElement?
    let source: SelectionSource
    /// The app the selection came from, for clipboard snapshots that have no
    /// usable AX element.
    let appPID: pid_t?
}

enum SelectionService {

    private static let log = Logger(subsystem: "dev.harsh.quietspeech", category: "selection")
    private static let maxSelectionLength = 12_000
    private static let maxContextLength = 12_000

    static func snapshot(in app: NSRunningApplication?) async -> SelectionSnapshot? {
        guard AXIsProcessTrusted() else { return nil }

        if let focus = focusedElement(), !isSecure(focus) {
            if let text = selectedText(in: focus), usable(text) {
                return SelectionSnapshot(
                    text: text,
                    element: focus,
                    focus: focus,
                    source: .accessibility,
                    appPID: app?.processIdentifier
                )
            }

            // Web views (Chrome, Electron, Safari) often report the focused
            // node as an AXWebArea without a selection. The selected text
            // lives on a descendant, so look for it before giving up.
            var budget = 500
            if let (element, text) = selectionInTree(focus, depth: 0, budget: &budget), usable(text) {
                log.debug("selection: found on descendant role=\(self.role(of: element), privacy: .public)")
                return SelectionSnapshot(
                    text: text,
                    element: element,
                    focus: focus,
                    source: .accessibility,
                    appPID: app?.processIdentifier
                )
            }
            log.debug("selection: none via AX (role=\(self.role(of: focus), privacy: .public))")
        }

        // Chrome exposes no accessibility tree until a screen reader asks for
        // it, and AXManualAccessibility does not reliably wake it. Fall back to
        // a clipboard copy for web and Electron editors, where Cmd+C is the
        // standard copy command.
        guard let app = app ?? NSWorkspace.shared.frontmostApplication,
              app != NSRunningApplication.current,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              canCopySelection(from: app) else {
            return nil
        }
        if let text = await PasteService.copySelection(), usable(text) {
            log.debug("selection: copied from \(app.bundleIdentifier ?? "unknown", privacy: .public)")
            return SelectionSnapshot(
                text: text,
                element: nil,
                focus: nil,
                source: .clipboard,
                appPID: app.processIdentifier
            )
        }

        log.debug("selection: none")
        return nil
    }

    static func contextText() -> String? {
        guard AXIsProcessTrusted(),
              let element = focusedElement(),
              !isSecure(element) else {
            return nil
        }

        if let selected = stringAttribute(kAXSelectedTextAttribute as CFString, of: element),
           let text = usableContext(selected) {
            return text
        }
        if let value = stringAttribute(kAXValueAttribute as CFString, of: element),
           let text = usableContext(value) {
            return text
        }
        return nil
    }

    private static func selectionInTree(_ element: AXUIElement,
                                        depth: Int,
                                        budget: inout Int) -> (AXUIElement, String)? {
        guard depth < 8, budget > 0 else { return nil }
        guard let children = attribute(kAXChildrenAttribute as CFString, of: element) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            budget -= 1
            guard budget > 0 else { return nil }
            if !isSecure(child), let text = selectedText(in: child), usable(text) {
                return (child, text)
            }
            if let found = selectionInTree(child, depth: depth + 1, budget: &budget) {
                return found
            }
        }
        return nil
    }

    private static func usable(_ text: String) -> Bool {
        let meaningful = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !meaningful.isEmpty && text.count <= maxSelectionLength
    }

    /// Reads the selection from an element. Prefers AXSelectedText; falls back
    /// to slicing AXValue with AXSelectedTextRange for text controls that only
    /// expose a range.
    private static func selectedText(in element: AXUIElement) -> String? {
        if let text = stringAttribute(kAXSelectedTextAttribute as CFString, of: element),
           usable(text) {
            return text
        }
        guard let value = stringAttribute(kAXValueAttribute as CFString, of: element),
              let rangeValue = attribute(kAXSelectedTextRangeAttribute as CFString, of: element),
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(rangeValue, to: AXValue.self), .cfRange, &range),
              range.location != kCFNotFound,
              range.length > 0,
              range.location >= 0,
              range.location + range.length <= (value as NSString).length else {
            return nil
        }
        return (value as NSString).substring(with: NSRange(location: range.location, length: range.length))
    }

    private static func canCopySelection(from app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        if terminalApps.contains(id) { return false }
        if webApps.contains(id) || webPrefixes.contains(where: { id.hasPrefix($0) }) {
            return true
        }
        return isElectron(app)
    }

    private static let webApps: Set<String> = [
        "com.apple.Safari",
        "com.apple.Notes",
        "com.apple.mail",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "company.thebrowser.Browser",
        "com.tinyspeck.slackmacgap",
    ]

    private static let webPrefixes = ["com.google.Chrome"]

    /// Cmd+C sends an interrupt in these apps, so never synthesize it there.
    private static let terminalApps: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.cmuxterm.app",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
    ]

    private static func isElectron(_ app: NSRunningApplication) -> Bool {
        guard let bundleURL = app.bundleURL else { return false }
        let framework = bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Frameworks")
            .appendingPathComponent("Electron Framework.framework")
        return FileManager.default.fileExists(atPath: framework.path)
    }

    private static func role(of element: AXUIElement) -> String {
        stringAttribute(kAXRoleAttribute as CFString, of: element) ?? "unknown"
    }

    private static func attribute(_ attribute: CFString, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private static func usableContext(_ text: String) -> String? {
        let meaningful = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meaningful.isEmpty else { return nil }
        return String(text.prefix(maxContextLength))
    }

    static func isStillSelected(_ snapshot: SelectionSnapshot) async -> Bool {
        switch snapshot.source {
        case .accessibility:
            guard let focus = snapshot.focus,
                  let element = snapshot.element,
                  let focused = focusedElement(),
                  CFEqual(focused, focus) else {
                return false
            }
            if let current = selectedText(in: element) {
                return current == snapshot.text
            }
            // Some web views stop exposing AXSelectedText while the selection
            // is still there. Focus identity is the strongest signal left.
            return !CFEqual(focus, element)

        case .clipboard:
            guard let pid = snapshot.appPID,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let current = await PasteService.copySelection() else {
                return false
            }
            return current.trimmingCharacters(in: .whitespacesAndNewlines)
                == snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - AX plumbing

    private static func focusedElement() -> AXUIElement? {
        if let element = focusedElement(AXUIElementCreateSystemWide()) {
            return element
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Chrome and Electron build their accessibility tree lazily. Asking for
        // it explicitly is the difference between "no focused element" and a
        // usable AXWebArea.
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        return focusedElement(root)
    }

    private static func focusedElement(_ root: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute as CFString, of: element)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: element)
        return role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }

    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value else { return nil }
        return value as? String
    }
}
