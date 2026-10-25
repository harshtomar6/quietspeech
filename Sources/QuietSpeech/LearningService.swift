import AppKit
import ApplicationServices
import Learning
import os

private let learningLog = Logger(subsystem: "dev.harsh.quietspeech", category: "learning")

// MARK: - Names on screen

/// Reads the text in the focused window when a dictation starts, so names
/// in the thread or document being replied to can be expected. The text is
/// used for that one dictation and never stored.
enum ScreenContextReader {

    /// AX calls are cross-process, and a busy app answers slowly. Whatever has
    /// been read when this runs out is what gets used.
    private static let budget: TimeInterval = 0.12
    private static let maxNodes = 1_500
    private static let maxCharacters = 20_000
    /// Text this far either side of the caret, for long documents.
    private static let caretWindow = 4_000

    /// Returns what was read by the deadline. The walk checks the deadline
    /// between elements, but one slow call can still overrun it, so the
    /// caller is answered on time regardless and the walk finishes unheard.
    static func read(pid: pid_t) async -> String {
        let collected = Collected()
        return await withCheckedContinuation { continuation in
            let answer = Once(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                collect(pid: pid, deadline: Date().addingTimeInterval(budget), into: collected)
                answer.resume(collected.text)
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + budget + 0.02) {
                answer.resume(collected.text)
            }
        }
    }

    /// Text gathered so far, shared between the walk and the deadline.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var pieces: [String] = []
        private var count = 0

        var text: String { lock.withLock { pieces.joined(separator: "\n") } }
        var total: Int { lock.withLock { count } }

        func add(_ text: String?) {
            guard let text, !text.isEmpty else { return }
            lock.withLock {
                guard count < maxCharacters else { return }
                let piece = String(text.prefix(maxCharacters - count))
                pieces.append(piece)
                count += piece.count
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String, Never>?

        init(_ continuation: CheckedContinuation<String, Never>) { self.continuation = continuation }

        func resume(_ value: String) {
            lock.withLock {
                continuation?.resume(returning: value)
                continuation = nil
            }
        }
    }

    private static func collect(pid: pid_t, deadline: Date, into collected: Collected) {
        guard AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        // Electron apps (Slack among them) build their tree only when asked.
        // Other apps ignore this.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        let add = collected.add
        var total: Int { collected.total }

        if let focus = AXRead.element(kAXFocusedUIElementAttribute, of: app), !AXRead.isSecure(focus) {
            add(textAroundCaret(in: focus))
        }

        guard let window = AXRead.element(kAXFocusedWindowAttribute, of: app) else { return }
        add(AXRead.string(kAXTitleAttribute, of: window))

        // Breadth-first, so the visible structure (sidebars, headers, the
        // thread) is read before deep detail.
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < maxNodes, total < maxCharacters, Date() < deadline {
            let element = queue.removeFirst()
            visited += 1
            if AXRead.isSecure(element) { continue }
            switch AXRead.string(kAXRoleAttribute, of: element) {
            case "AXStaticText", "AXHeading", "AXLink", "AXCell":
                add(AXRead.string(kAXValueAttribute, of: element) ?? AXRead.string(kAXTitleAttribute, of: element))
            case "AXTextArea", "AXTextField":
                add(AXRead.string(kAXValueAttribute, of: element).map { String($0.prefix(caretWindow)) })
            default:
                break
            }
            if let children = AXRead.children(of: element) {
                queue.append(contentsOf: children)
            }
        }
        learningLog.debug("screen context: \(visited, privacy: .public) nodes, \(total, privacy: .public) chars")
    }

    private static func textAroundCaret(in element: AXUIElement) -> String? {
        guard let value = AXRead.string(kAXValueAttribute, of: element) else { return nil }
        let field = value as NSString
        let caret = AXRead.caret(of: element) ?? field.length
        let lower = max(0, caret - caretWindow)
        let upper = min(field.length, caret + caretWindow)
        guard upper > lower else { return nil }
        return field.substring(with: field.rangeOfComposedCharacterSequences(
            for: NSRange(location: lower, length: upper - lower)))
    }
}

// MARK: - Corrections

/// Watches the text field a dictation was typed into, and reports what the
/// user changed it to. Polls the field for a couple of minutes because a chat
/// message may be fixed and sent within seconds; the last version seen before
/// it disappears is the one compared.
@MainActor
final class CorrectionWatcher {

    /// The inserted text, and what that stretch of the field reads now.
    var onEdited: ((_ inserted: String, _ edited: String) -> Void)?

    private struct Watch {
        let element: AXUIElement
        let anchor: InsertionAnchor
        var latest: String
        let started: Date
    }

    private static let settleDelay: TimeInterval = 0.6
    private static let pollInterval: TimeInterval = 1
    private static let lifetime: TimeInterval = 120
    private static let maxValueLength = 100_000

    private var watch: Watch?
    private var timer: Timer?
    private var generation = 0

    func begin(inserted: String, pid: pid_t) {
        finish()
        generation &+= 1
        let current = generation
        // AX writes and pastes land asynchronously.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self, self.generation == current else { return }
            self.attach(inserted: inserted, pid: pid)
        }
    }

    /// Compares what has been seen so far and stops watching.
    func finish() {
        generation &+= 1
        timer?.invalidate()
        timer = nil
        guard let watch else { return }
        self.watch = nil
        let edited = watch.latest != watch.anchor.inserted
        learningLog.notice("corrections: stopped watching, edited=\(edited, privacy: .public)")
        if edited {
            onEdited?(watch.anchor.inserted, watch.latest)
        }
    }

    private func attach(inserted: String, pid: pid_t) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let element = AXRead.element(kAXFocusedUIElementAttribute, of: app),
              !AXRead.isSecure(element),
              let value = AXRead.string(kAXValueAttribute, of: element),
              value.utf16.count <= Self.maxValueLength,
              let anchor = InsertionAnchor(inserted: inserted, in: value, caret: AXRead.caret(of: element)) else {
            learningLog.notice("corrections: this field's text isn't readable; not watching")
            return
        }
        watch = Watch(element: element, anchor: anchor, latest: inserted, started: Date())
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        learningLog.notice("corrections: watching the field")
    }

    private func poll() {
        guard var watch else { return }
        guard Date().timeIntervalSince(watch.started) < Self.lifetime,
              let value = AXRead.string(kAXValueAttribute, of: watch.element),
              value.utf16.count <= Self.maxValueLength,
              let span = watch.anchor.span(in: value) else {
            // Timed out, the field went away, or the text around the dictation
            // changed (usually: the message was sent).
            finish()
            return
        }
        watch.latest = span
        self.watch = watch
    }
}

// MARK: - Dictionary

@MainActor
enum SpellingDictionary {
    /// Whether the system spell checker knows `word` in `language`. Names the
    /// user has taught it count as known.
    static func knows(_ word: String, language: String) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: language,
            wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
        return range.location == NSNotFound
    }
}

// MARK: - AX plumbing

private enum AXRead {
    static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? String
    }

    static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func children(of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    /// The caret's UTF-16 offset: the end of the selection.
    static func caret(of element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range),
              range.location != kCFNotFound else { return nil }
        return range.location + range.length
    }

    static func isSecure(_ element: AXUIElement) -> Bool {
        string(kAXRoleAttribute, of: element) == "AXSecureTextField"
            || string(kAXSubroleAttribute, of: element) == "AXSecureTextField"
    }
}
