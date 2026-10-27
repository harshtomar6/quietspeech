import AppKit
import ApplicationServices

/// How the text will be shaped for the app receiving it. Detection is local:
/// the bundle id, and for browsers the window title, decided once at the start
/// of a dictation.
enum ContextProfile: String, CaseIterable, Identifiable, Sendable {
    case generic, code, terminal, email, chat, document

    var id: String { rawValue }

    var label: String {
        switch self {
        case .generic: return "Generic"
        case .code: return "Code"
        case .terminal: return "Terminal"
        case .email: return "Email"
        case .chat: return "Chat"
        case .document: return "Document"
        }
    }

    var detail: String {
        switch self {
        case .generic: return "Everyday prose: normal capitalization and punctuation."
        case .code: return "No auto-capitalization or final period, plus spoken code symbols."
        case .terminal: return "Shell-friendly: no capitalization, code symbols and flags."
        case .email: return "Normal sentences, plus “name at domain dot com” addresses."
        case .chat: return "Keeps chat text close to how you spoke it, and “at Priya” becomes @Priya."
        case .document: return "Paragraphs and lists for notes and documents."
        }
    }

    /// Code and terminals should never be "tidied" into prose.
    var isCodeLike: Bool { self == .code || self == .terminal }

    var capitalizesSentences: Bool { !isCodeLike }

    var addsTerminalPunctuation: Bool { !isCodeLike }

    var usesCodeSymbols: Bool { isCodeLike }
}

/// The user's choice: follow detection, or pin one profile.
enum ContextMode: String, CaseIterable, Identifiable, Sendable {
    case auto, generic, code, terminal, email, chat, document

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto (recommended)"
        default: return profile?.label ?? rawValue
        }
    }

    var profile: ContextProfile? {
        switch self {
        case .auto: return nil
        case .generic: return .generic
        case .code: return .code
        case .terminal: return .terminal
        case .email: return .email
        case .chat: return .chat
        case .document: return .document
        }
    }
}

/// Maps the frontmost app — and, for browsers, the tab title — onto a profile.
enum ContextDetector {

    static func detect(for app: NSRunningApplication?) -> ContextProfile {
        guard let app, let bundleID = app.bundleIdentifier else { return .generic }

        if let direct = profile(forBundleID: bundleID) {
            return direct
        }

        guard isBrowser(bundleID) else { return .generic }
        guard let title = windowTitle(for: app)?.lowercased() else { return .generic }
        return profile(forBrowserTitle: title) ?? .generic
    }

    // MARK: - Bundle ids

    private static func profile(forBundleID id: String) -> ContextProfile? {
        terminalIDs.contains(id) ? .terminal
            : codeIDs.contains(id) || id.hasPrefix("com.jetbrains.") ? .code
            : emailIDs.contains(id) ? .email
            : chatIDs.contains(id) ? .chat
            : documentIDs.contains(id) ? .document
            : nil
    }

    private static let terminalIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "co.zeit.hyper",
        "org.tabby",
    ]

    private static let codeIDs: Set<String> = [
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.panic.Nova",
        "com.barebones.bbedit",
        "com.macromates.TextMate",
        "com.google.android.studio",
        "org.gnu.Emacs",
        "com.github.atom",
    ]

    private static let emailIDs: Set<String> = [
        "com.apple.mail",
        "com.microsoft.Outlook",
        "com.readdle.smartemail-Mac",
        "com.mimestream.Mimestream",
        "com.superhuman.electron",
    ]

    private static let chatIDs: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.apple.MobileSMS",
        "net.whatsapp.WhatsApp",
        "org.telegram.desktop",
        "ru.keepcoder.Telegram",
        "com.microsoft.teams2",
        "com.microsoft.teams",
    ]

    private static let documentIDs: Set<String> = [
        "com.apple.Notes",
        "notion.id",
        "md.obsidian",
        "com.apple.TextEdit",
        "com.apple.iWork.Pages",
        "com.microsoft.Word",
        "net.shinyfrog.bear",
        "com.apple.iWork.Keynote",
        "com.apple.iWork.Numbers",
    ]

    private static func isBrowser(_ id: String) -> Bool {
        let prefixes = [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera",
        ]
        return prefixes.contains { id.hasPrefix($0) }
    }

    private static func profile(forBrowserTitle title: String) -> ContextProfile? {
        let emailMarkers = ["gmail", "outlook", " - mail", "protonmail", "proton mail",
                            "yahoo mail", "zoho mail", "superhuman"]
        if emailMarkers.contains(where: title.contains) { return .email }

        let chatMarkers = ["slack", "discord", "whatsapp", "telegram", "teams", "messenger"]
        if chatMarkers.contains(where: title.contains) { return .chat }

        let documentMarkers = ["google docs", "google sheets", "google slides",
                               "notion", "confluence", "coda", "quip"]
        if documentMarkers.contains(where: title.contains) { return .document }

        return nil
    }

    // MARK: - Window title

    /// AX gives the tab title for browsers, which is what tells Gmail apart
    /// from GitHub. Needs Accessibility, which insertion already requires.
    static func windowTitle(for app: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &windowValue
        ) == .success, let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }

        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, kAXTitleAttribute as CFString, &titleValue
        ) == .success, let titleValue else { return nil }
        return titleValue as? String
    }
}
