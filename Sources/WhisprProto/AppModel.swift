import SwiftUI
import Observation
import AppKit
import os

@MainActor
@Observable
final class AppModel {

    enum CleanMode: String, CaseIterable, Identifiable {
        case off, rules
        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: return "Off (raw)"
            case .rules: return "Rules (instant)"
            }
        }
    }

    enum Language: String, CaseIterable, Identifiable {
        case englishUS = "en-US"
        case englishGB = "en-GB"
        case englishIN = "en-IN"
        case spanish = "es-ES"
        case french = "fr-FR"
        case german = "de-DE"
        case hindi = "hi-IN"
        case japanese = "ja-JP"
        case chineseSimplified = "zh-CN"

        var id: String { rawValue }
        var label: String {
            Locale(identifier: rawValue).localizedString(forIdentifier: rawValue) ?? rawValue
        }
        var locale: Locale { Locale(identifier: rawValue) }
    }

    /// Which overlay the HUD draws while dictating.
    enum OverlayStyle: String, CaseIterable, Identifiable {
        case capsule, card
        var id: String { rawValue }
        var label: String {
            switch self {
            case .capsule: return "Capsule"
            case .card: return "Card"
            }
        }
        var detail: String {
            switch self {
            case .capsule: return "A single slim line of live text with a level meter and timer."
            case .card: return "A small card that names the app your words will be typed into."
            }
        }
    }

    /// What the overlay is showing. Tracked explicitly because "done" happens
    /// after `isRecording` has already gone false.
    enum OverlayPhase { case listening, done, error }

    // MARK: Session state
    var isRecording = false
    var finalizedText = ""
    var volatileText = ""
    var cleanedText = ""
    var status = "Idle"
    var errorMessage: String?
    var overlayPhase: OverlayPhase = .done
    /// Kept until the overlay fades out so the timer shows the full length.
    var recordingStartedAt: Date?

    // MARK: Overlay preview
    /// Set only while the Settings preview is running; overrides live data so
    /// previewing a style never disturbs a real transcript.
    var previewText: String?
    var previewLevels: [Float]?
    var previewLevel: Float?

    // MARK: Live audio visualisation
    var level: Float = 0
    var levels: [Float] = []

    // MARK: Preferences
    var language: Language = .englishUS
    var cleanMode: CleanMode = .rules
    /// Hold-to-talk, tap-to-toggle and paste-again bindings. Defaults to Fn to
    /// hold and Fn+Cmd to tap, which is also the latch: start holding Fn, add
    /// Cmd, and the recording keeps going in toggle mode.
    var shortcutConfiguration: ShortcutConfiguration = .defaultConfiguration
    var autoInsert = true
    /// Insert at the caret via the Accessibility API, falling back to paste.
    var useDirectInsertion = true
    var overlayStyle: OverlayStyle = .capsule

    /// First run shows the guided setup window instead of settings.
    var onboardingCompleted = false

    /// Temporary: append each finished dictation (raw and cleaned) to a local
    /// file so the cleanup rules can be checked against real speech.
    var captureDictations = false
    var captureStatus = ""

    // MARK: Permissions
    var microphoneGranted = false
    /// Accessibility covers both typing the transcript into other apps and
    /// watching the Fn key, so there is no separate Input Monitoring prompt.
    var accessibilityGranted = false

    // MARK: Internals
    private let engine = SpeechEngine()
    private let shortcuts = ShortcutBackend()
    private let hud = HUDController()
    private(set) var targetApp: NSRunningApplication?
    /// Turns matcher edges into start/stop/switchedToToggle.
    private var shortcutSession = DictationShortcutSessionController()
    /// The last text typed into another app, for Paste Again.
    private(set) var lastInsertedText = ""
    /// Re-entrancy guard for `refreshPermissions()`.
    private var isRefreshingPermissions = false
    private var previewTask: Task<Void, Never>?
    private let permLog = Logger(subsystem: "dev.harsh.whisprproto", category: "permissions")
    private let insertLog = Logger(subsystem: "dev.harsh.whisprproto", category: "insert")
    private let shortcutLog = Logger(subsystem: "dev.harsh.whisprproto", category: "shortcut")

    var rawText: String { finalizedText + volatileText }

    var overlayElapsed: TimeInterval {
        guard let recordingStartedAt else { return 0 }
        return Date().timeIntervalSince(recordingStartedAt)
    }

    var shortcutDisplay: String {
        shortcutConfiguration.summary
    }

    init() {
        loadPreferences()
        refreshCaptureStatus()
        wireShortcuts()
        shortcuts.apply(configuration: shortcutConfiguration)
        refreshPermissions()
    }

    // MARK: - Dictation control

    func beginDictation() {
        guard !isRecording else { return }
        Task { await start() }
    }

    func toggleDictation() {
        if isRecording {
            Task { await stop() }
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        // Captured before any await: did the shortcut session ask for this?
        let startedByShortcut = shortcutSession.isActive

        guard await Permissions.requestMicrophone() else {
            microphoneGranted = false
            errorMessage = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone, then relaunch."
            return
        }
        microphoneGranted = true

        // Remember where to type the result back into.
        targetApp = NSWorkspace.shared.frontmostApplication

        finalizedText = ""
        volatileText = ""
        cleanedText = ""
        level = 0
        levels = []

        engine.onResult = { [weak self] text, isFinal in
            guard let self else { return }
            if isFinal {
                self.finalizedText += text
                self.volatileText = ""
            } else {
                self.volatileText = text
            }
            self.refreshCleaned()
        }
        engine.onError = { [weak self] error in
            self?.errorMessage = error.localizedDescription
            self?.status = "Error"
            self?.overlayPhase = .error
        }
        engine.onStatus = { [weak self] message in
            self?.status = message
        }
        engine.onAudioLevel = { [weak self] value in
            Task { @MainActor in self?.pushLevel(value) }
        }

        do {
            try await engine.start(locale: language.locale)
            isRecording = true
            status = "Listening…"
            recordingStartedAt = Date()
            overlayPhase = .listening
            hud.show(model: self)
            shortcutLog.notice("engine listening")
        } catch {
            shortcutLog.error("engine start failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            status = "Idle"
            overlayPhase = .error
            return
        }

        // The user may have released the trigger while the engine was starting —
        // a quick tap in hold-to-talk mode, or a tap-to-toggle where the second
        // press landed mid-launch. If the session that asked for this recording
        // has since ended, don't leave the mic running.
        if startedByShortcut && !shortcutSession.isActive {
            shortcutLog.notice("session ended during launch -> stopping")
            await stop()
        }
    }

    func stop() async {
        guard isRecording else {
            shortcutLog.notice("stop ignored: engine was not recording")
            return
        }
        // Whatever stopped us — trigger, menu, overlay — the session is over.
        shortcutSession.sessionDidStopExternally()
        status = "Finishing…"
        await engine.stop()
        isRecording = false
        shortcutLog.notice("engine stopped")

        cleanedText = cleanedTextForCurrentMode()
        captureDictation(raw: rawText, cleaned: cleanedText)
        if overlayPhase != .error { overlayPhase = .done }

        status = "Idle"

        if autoInsert {
            insertIntoFrontmostApp(target: targetApp)
        }

        // Let the overlay show the finished text, then fade it out.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self, !self.isRecording else { return }
            self.hud.hide()
        }
    }

    // MARK: - Audio level

    private func pushLevel(_ value: Float) {
        let shaped = powf(value, 0.65)
        level = max(shaped, level * 0.72)
        levels.append(level)
        if levels.count > 72 {
            levels.removeFirst(levels.count - 72)
        }
    }

    // MARK: - Cleanup

    private func cleanedTextForCurrentMode() -> String {
        switch cleanMode {
        case .off: return rawText
        case .rules: return RuleCleaner.clean(rawText)
        }
    }

    func refreshCleaned() {
        switch cleanMode {
        case .off: cleanedText = rawText
        case .rules: cleanedText = RuleCleaner.clean(rawText)
        }
    }

    func completeOnboarding() {
        onboardingCompleted = true
        persistPreferences()
    }

    // MARK: - Cleanup capture

    /// Temporary debugging aid: appends each dictation, raw and cleaned, to a
    /// local file so the cleanup rules can be reviewed against real speech.
    /// Off by default, and the file never leaves this Mac.
    static var captureFileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("WhisprProto/dictation-capture.jsonl")
    }

    private func captureDictation(raw: String, cleaned: String) {
        guard captureDictations else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry: [String: String] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "app": targetApp?.localizedName ?? "",
            "raw": trimmed,
            "cleaned": cleaned,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let line = String(data: data, encoding: .utf8) else { return }

        let url = Self.captureFileURL
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        refreshCaptureStatus()
    }

    func refreshCaptureStatus() {
        let url = Self.captureFileURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int else {
            captureStatus = "No capture file yet."
            return
        }
        let count = (try? String(contentsOf: url, encoding: .utf8))?
            .split(separator: "\n").filter { !$0.isEmpty }.count ?? 0
        captureStatus = "\(count) dictation\(count == 1 ? "" : "s") \u{00b7} \(max(size / 1024, 1)) KB"
    }

    func revealCaptureFile() {
        let url = Self.captureFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            captureStatus = "No capture file yet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clearCaptureFile() {
        try? FileManager.default.removeItem(at: Self.captureFileURL)
        refreshCaptureStatus()
    }

    // MARK: - Insertion

    func insertText() {
        insertIntoFrontmostApp(target: targetApp)
    }

    /// Re-types the last dictation into whatever app is frontmost now, for the
    /// Paste Again binding.
    func pasteAgain() {
        guard !lastInsertedText.isEmpty else { return }
        insertIntoFrontmostApp(target: NSWorkspace.shared.frontmostApplication)
    }

    private func insertIntoFrontmostApp(target: NSRunningApplication?) {
        let text = cleanedText.isEmpty ? rawText : cleanedText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        guard Permissions.accessibilityGranted else {
            accessibilityGranted = false
            errorMessage = "Text is ready, but Accessibility permission is needed to type it into other apps."
            return
        }

        lastInsertedText = text

        // Hand focus back to the app the user was in before we became active.
        if let target, target != NSRunningApplication.current {
            target.activate(options: [])
        }

        // Three-tier insertion, cheapest and cleanest first:
        //   1. Accessibility write — no clipboard, instant.
        //   2. Synthetic typing — no clipboard, works where AX can't.
        //   3. Paste — borrows the clipboard, so last resort.
        if useDirectInsertion {
            if AXInsertService.insert(text) {
                insertLog.notice("insertion path: accessibility")
                return
            }
            if TypingService.type(text) {
                insertLog.notice("insertion path: synthetic typing")
                return
            }
        }

        if PasteService.insert(text) {
            insertLog.notice("insertion path: clipboard paste")
        } else {
            errorMessage = "Could not insert text. Check Accessibility permission."
        }
    }

    // MARK: - Activation

    private func wireShortcuts() {
        shortcuts.onEvent = { [weak self] event in
            self?.handleShortcutEvent(event)
        }
        shortcuts.onTapUnavailable = { [weak self] message in
            guard let self else { return }
            self.hotkeyError(message)
        }
        shortcuts.onTapStatusChanged = { [weak self] active in
            guard let self else { return }
            self.accessibilityGranted = Permissions.accessibilityGranted
            if active { self.errorMessage = nil }
        }
        // Advisory: the AX write reported success but a later read-back didn't
        // reflect it. We deliberately do NOT paste here — that's what caused
        // doubled insertions. Just point the user at Copy.
        AXInsertService.onUnverifiedInsert = { [weak self] in
            self?.errorMessage = "Text may not have reached the app — it's in the transcript above if you need Copy."
        }
    }

    private func handleShortcutEvent(_ event: ShortcutEvent) {
        if event == .copyAgainTriggered {
            shortcutLog.notice("event copyAgainTriggered -> paste again")
            pasteAgain()
            return
        }

        let actions = shortcutSession.handle(event)
        shortcutLog.notice("""
        event \(String(describing: event), privacy: .public) -> \
        \(actions.map { String(describing: $0) }.joined(separator: ", "), privacy: .public)
        """)

        for action in actions {
            switch action {
            case .start(let mode):
                shortcutLog.notice("dictation start (\(mode.rawValue, privacy: .public))")
                beginDictation()
            case .stop:
                shortcutLog.notice("dictation stop")
                Task { await self.stop() }
            case .switchedToToggle:
                // Fn was being held and Cmd just joined it. The recording and
                // the audio keep running; only the way it ends has changed.
                shortcutLog.notice("latched into toggle mode")
            }
        }
    }

    private func hotkeyError(_ message: String) {
        errorMessage = message
        refreshPermissions()
    }

    func applyActivation() {
        shortcuts.apply(configuration: shortcutConfiguration)
    }

    /// Assigns one of the three bindings and re-arms the tap. Conflicts are
    /// surfaced in the UI rather than silently rejected — an overlapping pair
    /// is the user's call to make.
    func setBinding(_ binding: ShortcutBinding, for role: ShortcutRole) {
        shortcutConfiguration = shortcutConfiguration.replacing(role, with: binding)
        applyActivation()
        persistPreferences()
    }

    /// While the settings recorder is listening for keys, the global tap must
    /// stop reacting to them — otherwise recording "Fn" would start a dictation.
    func setShortcutCapture(_ capturing: Bool) {
        shortcuts.setCaptureMode(capturing)
    }

    // MARK: Permissions

    func refreshPermissions() {
        // ensureTap() reports failures via onTapUnavailable, which calls back
        // into hotkeyError() -> refreshPermissions(). Without this guard a
        // missing Accessibility grant would recurse without bound.
        guard !isRefreshingPermissions else { return }
        isRefreshingPermissions = true
        defer { isRefreshingPermissions = false }

        microphoneGranted = Permissions.microphoneGranted
        accessibilityGranted = Permissions.accessibilityGranted

        // The listener is an *active* event tap, gated on Accessibility
        // (kTCCServicePostEvent). tapCreate returns nil for an active tap when
        // the grant is missing, so this both starts the tap and verifies the
        // permission.
        if !shortcutConfiguration.isDisabled {
            shortcuts.ensureTap()
        }

        permLog.notice("""
        perms mic=\(self.microphoneGranted, privacy: .public) \
        ax=\(self.accessibilityGranted, privacy: .public) \
        tap=\(self.shortcuts.tapActive, privacy: .public) \
        bindings=\(self.shortcutConfiguration.summary, privacy: .public) \
        axTrustedRaw=\(Permissions.accessibilityDebug, privacy: .public)
        """)
    }

    func requestAccessibility() {
        Permissions.promptAccessibility()
        refreshPermissions()
    }

    /// TCC caches per process: the reliable fix after granting is a relaunch.
    func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Preferences persistence

    func persistPreferences() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(shortcutConfiguration) {
            defaults.set(data, forKey: "shortcutConfiguration")
        }
        defaults.set(autoInsert, forKey: "autoInsert")
        defaults.set(useDirectInsertion, forKey: "useDirectInsertion")
        defaults.set(overlayStyle.rawValue, forKey: "overlayStyle")
        defaults.set(captureDictations, forKey: "captureDictations")
        defaults.set(onboardingCompleted, forKey: "onboardingCompleted")
        defaults.set(cleanMode.rawValue, forKey: "cleanMode")
        defaults.set(language.rawValue, forKey: "language")
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "shortcutConfiguration"),
           let value = try? JSONDecoder().decode(ShortcutConfiguration.self, from: data) {
            shortcutConfiguration = value
        } else {
            shortcutConfiguration = Self.migrateLegacyTrigger(defaults)
            // migrateLegacyTrigger drops the old keys, so write the replacement
            // in the same breath rather than leaving neither behind.
            if let data = try? JSONEncoder().encode(shortcutConfiguration) {
                defaults.set(data, forKey: "shortcutConfiguration")
            }
        }
        if defaults.object(forKey: "autoInsert") != nil {
            autoInsert = defaults.bool(forKey: "autoInsert")
        }
        if defaults.object(forKey: "useDirectInsertion") != nil {
            useDirectInsertion = defaults.bool(forKey: "useDirectInsertion")
        }
        if let raw = defaults.string(forKey: "overlayStyle"),
           let value = OverlayStyle(rawValue: raw) {
            overlayStyle = value
        }
        if defaults.object(forKey: "captureDictations") != nil {
            captureDictations = defaults.bool(forKey: "captureDictations")
        }
        if defaults.object(forKey: "onboardingCompleted") != nil {
            onboardingCompleted = defaults.bool(forKey: "onboardingCompleted")
        }
        if let raw = defaults.string(forKey: "cleanMode"), let value = CleanMode(rawValue: raw) {
            cleanMode = value
        }
        if let raw = defaults.string(forKey: "language"), let value = Language(rawValue: raw) {
            language = value
        }
    }

    /// The pre-ShortcutCore preferences stored a single trigger. Translate it
    /// once so nobody's setup resets on upgrade, then drop the old keys.
    private static func migrateLegacyTrigger(_ defaults: UserDefaults) -> ShortcutConfiguration {
        guard let raw = defaults.string(forKey: "triggerSource") else {
            return .defaultConfiguration
        }

        let holdToTalk = (defaults.object(forKey: "holdToTalk") as? Bool) ?? true

        var configuration = ShortcutConfiguration.defaultConfiguration
        switch raw {
        case "off":
            configuration = .disabled
        case "shortcut":
            let keyCode = UInt16(defaults.integer(forKey: "shortcutKeyCode"))
            let binding = ShortcutBinding(
                keyCode: keyCode,
                keyDisplay: ShortcutKeyNames.name(forKeyCode: keyCode),
                modifiers: ShortcutModifiers(nsEventFlags: UInt(defaults.integer(forKey: "shortcutModifiers"))),
                kind: .key,
                preset: nil
            )
            configuration = ShortcutConfiguration(
                hold: holdToTalk ? binding : .disabled,
                toggle: holdToTalk ? .disabled : binding
            )
        default:
            configuration = .defaultConfiguration
        }

        for key in ["triggerSource", "holdToTalk", "shortcutKeyCode", "shortcutModifiers"] {
            defaults.removeObject(forKey: key)
        }
        return configuration
    }

    // MARK: - Overlay preview

    /// Shows the HUD with stand-in content so a style can be judged without
    /// dictating. Uses the preview fields, so a real transcript is untouched.
    func previewOverlay() {
        guard !isRecording else { return }
        previewTask?.cancel()

        let previousPhase = overlayPhase
        previewText = "This is how the overlay looks while you dictate."
        previewLevel = 0.6
        previewLevels = (0..<72).map { _ in Float.random(in: 0.06...0.92) }
        recordingStartedAt = Date()
        overlayPhase = .listening
        hud.show(model: self)

        previewTask = Task { [weak self] in
            for _ in 0..<28 {
                try? await Task.sleep(nanoseconds: 90_000_000)
                guard let self, !Task.isCancelled else { return }
                var values = self.previewLevels ?? []
                values.append(Float.random(in: 0.06...0.92))
                if values.count > 72 { values.removeFirst(values.count - 72) }
                self.previewLevels = values
            }
            guard let self, !Task.isCancelled else { return }
            self.hud.hide()
            self.previewText = nil
            self.previewLevels = nil
            self.previewLevel = nil
            self.recordingStartedAt = nil
            self.overlayPhase = previousPhase
        }
    }

    // MARK: - Misc

    func clear() {
        finalizedText = ""
        volatileText = ""
        cleanedText = ""
        levels = []
        level = 0
        errorMessage = nil
        overlayPhase = .done
        recordingStartedAt = nil
    }
}
