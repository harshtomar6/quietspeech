import SwiftUI
import Observation
import AppKit
import os
import Licensing
import Learning

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

        var transcriptionCode: String {
            switch self {
            case .englishUS, .englishGB, .englishIN: return "en"
            case .spanish: return "es"
            case .french: return "fr"
            case .german: return "de"
            case .hindi: return "hi"
            case .japanese: return "ja"
            case .chineseSimplified: return "zh"
            }
        }
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
    enum OverlayPhase { case listening, processing, done, error }
    enum AIProcessing { case polish, edit, generate, transcribe }

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
    /// Names, products and jargon the on-device recognizer should expect.
    var customVocabulary: [String] = []
    /// Spoken phrase → written form, applied after cleanup in one pass.
    var wordReplacements: [WordReplacement] = []
    /// Expect the names in the focused window for each dictation.
    var learnFromScreen = true
    /// Learn names the user fixes after a dictation is typed in.
    var learnFromCorrections = true
    /// Vocabulary added from corrections rather than typed in by the user.
    var learnedVocabulary: Set<String> = []
    /// Shown briefly in the overlay when a correction is learned.
    var learningNotice: String?
    /// Keep each finished dictation on this Mac so it can be recovered.
    var historyEnabled = true
    var history: [DictationRecord] = []

    // MARK: AI (bring your own key)
    var aiProvider: AIProvider = .apple
    private var aiProviderConfigs: [String: AIProviderConfig] = [:]
    var aiEnabled = false
    var aiPolishEnabled = false
    var aiGenerateEnabled = false
    var aiGenerateTrigger = "generate"
    var aiTranscriptionEnabled = true
    var aiTranscriptionModel = "whisper-1"
    var aiTranscriptionModels: [String: String] = [:]
    var aiEndpoint = "https://api.openai.com/v1"
    var aiModel = "gpt-4.1-mini"
    private(set) var aiKeyConfigured = false
    var isEditSession = false
    var isGenerateSession = false
    var aiProcessing: AIProcessing?

    /// Auto-detected from the frontmost app, or pinned by the user.
    var contextMode: ContextMode = .auto
    /// The profile in force for the current (or most recent) dictation.
    var activeProfile: ContextProfile = .generic
    private(set) var activeProfileWasDetected = true
    private(set) var hasContext = false
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
    var requestedSettingsPane: SettingsPane?
    let license = LicenseService()

    /// The cleanup capture is a development aid, so release builds leave it
    /// out unless turned on with
    /// `defaults write dev.harsh.quietspeech developerTools -bool YES`.
    static var developerToolsEnabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "developerTools")
        #endif
    }

    /// Temporary: append each finished dictation (raw and cleaned) to a local
    /// file so the cleanup rules can be checked against real speech.
    var captureDictations = false
    var captureStatus = ""
    /// Developer tools: keep each dictation's audio with Apple's live
    /// transcript, so recognizers can be compared with scripts/speech-bench.
    var saveAudioClips = false
    var clipStatus = ""

    // MARK: Permissions
    var microphoneGranted = false
    /// Accessibility covers both typing the transcript into other apps and
    /// watching the Fn key, so there is no separate Input Monitoring prompt.
    var accessibilityGranted = false

    // MARK: Internals
    private let engine = SpeechEngine()
    private let shortcuts = ShortcutBackend()
    private let hud = HUDController()
    private let correctionWatcher = CorrectionWatcher()
    private var correctionTally = CorrectionTally()
    private var isStartingDictation = false
    private(set) var targetApp: NSRunningApplication?
    /// Turns matcher edges into start/stop/switchedToToggle.
    private var shortcutSession = DictationShortcutSessionController()
    private var pendingSelection: SelectionSnapshot?
    private var pendingContext: String?
    private var remoteTranscriptionThisSession = false
    private var savesClipThisSession = false
    /// Names that a spoken "at <name>" may mention in this dictation: the
    /// user's vocabulary and the names read from the screen.
    private var mentionNames: [String] = []

    /// Fn released sooner than this after being pressed is a tap, not
    /// dictation: the session is dropped without showing the overlay.
    private static let tapThreshold: TimeInterval = 0.3
    /// When the hold binding (Fn) started the current session; nil for the
    /// toggle binding and the menu, which show the overlay at once.
    private var holdPressedAt: Date?
    /// Set when Fn came back up within `tapThreshold`.
    private var discardOnStop = false
    /// Shows the overlay once a hold has lasted `tapThreshold`.
    private var overlayRevealTask: Task<Void, Never>?
    private var sessionGeneration = 0
    /// The last text typed into another app, for Paste Again.
    private(set) var lastInsertedText = ""
    /// Re-entrancy guard for `refreshPermissions()`.
    private var isRefreshingPermissions = false
    private var previewTask: Task<Void, Never>?
    private let permLog = Logger(subsystem: "dev.harsh.quietspeech", category: "permissions")
    private let insertLog = Logger(subsystem: "dev.harsh.quietspeech", category: "insert")
    private let shortcutLog = Logger(subsystem: "dev.harsh.quietspeech", category: "shortcut")
    private let contextLog = Logger(subsystem: "dev.harsh.quietspeech", category: "context")
    private let aiLog = Logger(subsystem: "dev.harsh.quietspeech", category: "ai")

    var rawText: String { finalizedText + volatileText }

    var aiConfigured: Bool {
        if aiProvider == .apple {
            return AIService.appleIntelligenceAvailable
        }
        let endpoint = aiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, !model.isEmpty else { return false }
        return aiKeyConfigured || AIService.isLocalEndpoint(endpoint)
    }

    var aiRunsOnDevice: Bool {
        aiProvider == .apple || AIService.isLocalEndpoint(aiEndpoint)
    }

    var appleIntelligenceAvailable: Bool { AIService.appleIntelligenceAvailable }
    var appleIntelligenceStatus: String { AIService.appleIntelligenceAvailabilityDescription }

    var aiEditReady: Bool { aiEnabled && aiConfigured }
    var aiPolishReady: Bool { aiPolishEnabled && aiConfigured }
    var aiGenerateReady: Bool { aiGenerateEnabled && aiConfigured }
    var providerTranscriptionActive: Bool {
        aiTranscriptionEnabled
            && aiProvider.supportsProviderTranscription
            && aiConfigured
            && !aiTranscriptionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var aiReady: Bool {
        providerTranscriptionActive || (aiConfigured && (aiEnabled || aiPolishEnabled || aiGenerateEnabled))
    }
    var generateTriggerDisplay: String {
        aiGenerateTrigger
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? "generate"
    }

    private var aiConfiguration: AIService.Configuration? {
        if aiProvider == .apple {
            guard AIService.appleIntelligenceAvailable else { return nil }
            return AIService.Configuration(
                provider: .apple,
                endpoint: "",
                model: "Apple Intelligence",
                apiKey: ""
            )
        }

        let endpoint = aiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, !model.isEmpty else { return nil }
        let key = AIKeychain.read(for: aiProvider) ?? ""
        guard !key.isEmpty || AIService.isLocalEndpoint(endpoint) else { return nil }
        return AIService.Configuration(
            provider: aiProvider,
            endpoint: endpoint,
            model: model,
            apiKey: key
        )
    }

    var overlayElapsed: TimeInterval {
        guard let recordingStartedAt else { return 0 }
        return Date().timeIntervalSince(recordingStartedAt)
    }

    var shortcutDisplay: String {
        shortcutConfiguration.summary
    }

    init() {
        loadPreferences()
        let legacyTarget = aiProvider.usesEndpoint
            ? aiProvider
            : Self.inferAIProvider(defaults: .standard)
        AIKeychain.migrateLegacyKey(to: legacyTarget)
        refreshAIKeyState()
        history = Self.loadHistory()
        refreshCaptureStatus()
        wireShortcuts()
        shortcuts.apply(configuration: shortcutConfiguration)
        refreshPermissions()

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            await self?.prepareLicensing()
        }
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
        guard license.canUseApp else {
            status = "Activate QuietSpeech"
            errorMessage = license.blockingMessage
            overlayPhase = .error
            LicenseWindowController.shared.present(model: self)
            return
        }
        errorMessage = nil
        // Captured before any await: did the shortcut session ask for this?
        let startedByShortcut = shortcutSession.isActive
        // The last dictation's field is judged before this one changes things,
        // quietly: the overlay is about to show the new dictation.
        isStartingDictation = true
        correctionWatcher.finish()
        isStartingDictation = false
        learningNotice = nil

        // Read the screen while the microphone and model get ready.
        var screenText: Task<String, Never>?
        if learnFromScreen, learningSupported,
           let app = NSWorkspace.shared.frontmostApplication,
           app != NSRunningApplication.current {
            let pid = app.processIdentifier
            screenText = Task { await ScreenContextReader.read(pid: pid) }
        }

        guard await Permissions.requestMicrophone() else {
            microphoneGranted = false
            errorMessage = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone, then relaunch."
            return
        }
        microphoneGranted = true

        sessionGeneration &+= 1

        // Remember where to type the result back into.
        targetApp = NSWorkspace.shared.frontmostApplication
        resolveContextProfile(for: targetApp)

        pendingSelection = nil
        pendingContext = nil
        isEditSession = false
        isGenerateSession = false
        aiProcessing = nil
        if aiEditReady || aiGenerateReady,
           let app = targetApp,
           app != NSRunningApplication.current {
            pendingSelection = await SelectionService.snapshot(in: app)
            isEditSession = aiEditReady && pendingSelection != nil
            if let selection = pendingSelection {
                aiLog.notice("selection captured: app=\(app.bundleIdentifier ?? "nil", privacy: .public) selection=\(selection.text.count, privacy: .public) chars edit=\(self.isEditSession, privacy: .public)")
            }
        }
        if aiGenerateReady, pendingSelection == nil,
           let app = targetApp,
           app != NSRunningApplication.current {
            pendingContext = SelectionService.contextText()
        }

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

        let onScreen = await screenText?.value
        let onScreenTerms = screenTerms(from: onScreen)
        engine.contextualStrings = customVocabulary + onScreenTerms
        mentionNames = customVocabulary + onScreenTerms
        remoteTranscriptionThisSession = providerTranscriptionActive
        savesClipThisSession = saveAudioClips && Self.developerToolsEnabled
        engine.recordsAudio = remoteTranscriptionThisSession || savesClipThisSession

        do {
            try await engine.start(locale: language.locale)
            isRecording = true
            status = "Listening…"
            recordingStartedAt = Date()
            overlayPhase = .listening
            revealOverlay()
            shortcutLog.notice("engine listening")
        } catch {
            shortcutLog.error("engine start failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            status = "Idle"
            overlayPhase = .error
            pendingSelection = nil
            isEditSession = false
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
        if discardOnStop {
            await discardTap()
            return
        }
        holdPressedAt = nil
        if overlayRevealTask != nil {
            overlayRevealTask?.cancel()
            overlayRevealTask = nil
            hud.show(model: self)
        }
        // Whatever stopped us — trigger, menu, overlay — the session is over.
        let generation = sessionGeneration
        shortcutSession.sessionDidStopExternally()
        status = "Finishing…"
        let audioURL = await engine.stop()
        isRecording = false
        shortcutLog.notice("engine stopped")
        if savesClipThisSession, let audioURL {
            // Before provider transcription replaces Apple's text.
            saveClip(audioURL)
        }

        if remoteTranscriptionThisSession,
           providerTranscriptionActive,
           let audioURL {
            await transcribeWithProvider(audioURL: audioURL, generation: generation)
            guard generation == sessionGeneration else { return }
        } else if let audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }

        let spoken = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if aiGenerateReady,
           let instruction = Self.generateInstruction(from: spoken, trigger: aiGenerateTrigger) {
            await finishGenerate(
                instruction: instruction,
                context: pendingSelection?.text ?? pendingContext ?? SelectionService.contextText(),
                generation: generation
            )
            return
        }

        if isEditSession, let selection = pendingSelection {
            await finishEdit(selection: selection)
            return
        }

        let raw = rawText
        let local = cleanedTextForCurrentMode()
        if aiPolishEnabled, aiConfigured, !activeProfile.isCodeLike {
            await finishPolish(base: local, raw: raw, generation: generation)
            return
        }
        finishDictation(cleaned: local, raw: raw)
    }

    private func transcribeWithProvider(audioURL: URL, generation: Int) async {
        defer { try? FileManager.default.removeItem(at: audioURL) }
        guard generation == sessionGeneration, let configuration = aiConfiguration else { return }

        status = "Transcribing…"
        overlayPhase = .processing
        aiProcessing = .transcribe
        let prompt = customVocabulary.joined(separator: ", ")
        let started = Date()

        do {
            let text = try await AIService.transcribe(
                audioURL: audioURL,
                model: aiTranscriptionModel,
                prompt: prompt,
                language: language.transcriptionCode,
                configuration: configuration
            )
            guard generation == sessionGeneration else { return }
            finalizedText = text
            volatileText = ""
            refreshCleaned()
            aiLog.notice("transcription ok: provider=\(self.aiProvider.rawValue, privacy: .public) chars=\(text.count, privacy: .public) ms=\(Int(Date().timeIntervalSince(started) * 1000), privacy: .public)")
        } catch {
            guard generation == sessionGeneration else { return }
            aiLog.error("provider transcription failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Provider transcription failed; used Apple’s on-device transcript. \(error.localizedDescription)"
        }
    }

    private func finishPolish(base: String, raw: String, generation: Int) async {
        guard !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finishDictation(cleaned: base, raw: raw)
            return
        }
        guard PolishGuard.shouldPolish(base), let configuration = aiConfiguration else {
            finishDictation(cleaned: base, raw: raw)
            return
        }

        cleanedText = base
        status = "Polishing…"
        overlayPhase = .processing
        aiProcessing = .polish
        aiLog.notice("polish request: app=\(self.targetApp?.bundleIdentifier ?? "nil", privacy: .public) chars=\(base.count, privacy: .public)")

        do {
            let result = try await AIService.polish(
                transcript: base,
                profile: activeProfile,
                configuration: configuration
            )
            guard generation == sessionGeneration else { return }
            if let reason = PolishGuard.rejection(polished: result, original: base)
                ?? (PolishPrompt.echoesExample(result, input: base) ? "echoed example" : nil) {
                aiLog.notice("polish rejected: reason=\(reason, privacy: .public) chars=\(result.count, privacy: .public)")
                finishDictation(cleaned: base, raw: raw)
                return
            }
            finishDictation(cleaned: result, raw: raw)
        } catch {
            guard generation == sessionGeneration else { return }
            aiLog.error("polish failed: \(error.localizedDescription, privacy: .public)")
            finishDictation(cleaned: base, raw: raw)
        }
    }

    private func finishDictation(cleaned: String, raw: String) {
        // Again after AI polish, which may have rewritten "@Priya" back to words.
        let cleaned = withMentions(cleaned)
        cleanedText = cleaned
        aiProcessing = nil
        captureDictation(raw: raw, cleaned: cleaned)
        recordHistory(raw: raw, cleaned: cleaned)
        if overlayPhase != .error { overlayPhase = .done }
        status = "Idle"
        if autoInsert {
            insertText(cleaned, target: targetApp)
            watchForCorrections(of: cleaned)
        }
        hideOverlay()
    }

    // MARK: - Generate Mode

    private func finishGenerate(instruction: String, context: String?, generation: Int) async {
        isGenerateSession = true
        isEditSession = false
        status = "Generating…"
        overlayPhase = .processing
        aiProcessing = .generate

        guard !instruction.isEmpty else {
            errorMessage = "Say what to generate after “\(generateTriggerDisplay)”."
            overlayPhase = .error
            status = "Idle"
            hideOverlay()
            return
        }
        guard let configuration = aiConfiguration else {
            errorMessage = aiProvider == .apple
                ? "Apple Intelligence is unavailable. \(appleIntelligenceStatus)"
                : "AI isn't configured. Add an endpoint, model and key in Settings."
            overlayPhase = .error
            status = "Idle"
            hideOverlay()
            return
        }

        aiLog.notice("generate request: app=\(self.targetApp?.bundleIdentifier ?? "nil", privacy: .public) instruction=\(instruction.count, privacy: .public) context=\(context?.count ?? 0, privacy: .public) chars")

        do {
            let result = try await AIService.generate(
                instruction: instruction,
                context: context,
                profile: activeProfile,
                configuration: configuration
            )
            guard generation == sessionGeneration else {
                aiLog.notice("discarding stale generate result")
                return
            }
            cleanedText = result
            captureDictation(raw: instruction, cleaned: result, kind: "generate")
            recordHistory(raw: instruction, cleaned: result)

            status = "Idle"
            overlayPhase = .done
            if autoInsert {
                insertText(result, target: targetApp)
            }
        } catch {
            guard generation == sessionGeneration else { return }
            aiLog.error("generate failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            overlayPhase = .error
            status = "Idle"
        }

        hideOverlay()
    }

    // MARK: - Edit Mode

    private func finishEdit(selection: SelectionSnapshot) async {
        let generation = sessionGeneration
        status = "Rewriting…"
        overlayPhase = .processing
        aiProcessing = .edit
        let instruction = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !instruction.isEmpty else {
            errorMessage = "No instruction heard. Select text and say what to change."
            overlayPhase = .error
            status = "Idle"
            hideOverlay()
            return
        }
        guard let configuration = aiConfiguration else {
            errorMessage = aiProvider == .apple
                ? "Apple Intelligence is unavailable. \(appleIntelligenceStatus)"
                : "AI isn't configured. Add an endpoint, model and key in Settings."
            overlayPhase = .error
            status = "Idle"
            hideOverlay()
            return
        }

        aiLog.notice("edit request: app=\(self.targetApp?.bundleIdentifier ?? "nil", privacy: .public) selection=\(selection.text.count, privacy: .public) instruction=\(instruction.count, privacy: .public) chars")

        do {
            let result = try await AIService.edit(
                selection: selection.text,
                instruction: instruction,
                profile: activeProfile,
                configuration: configuration
            )
            guard generation == sessionGeneration else {
                aiLog.notice("discarding stale edit result")
                return
            }
            cleanedText = result
            captureDictation(raw: instruction, cleaned: result, kind: "edit")
            recordHistory(raw: instruction, cleaned: result)

            guard await SelectionService.isStillSelected(selection) else {
                errorMessage = historyEnabled
                    ? "The selection changed before the rewrite finished — the result is in History."
                    : "The selection changed before the rewrite finished."
                overlayPhase = .error
                status = "Idle"
                hideOverlay()
                return
            }

            status = "Idle"
            overlayPhase = .done
            if autoInsert {
                insertText(result, target: targetApp)
            }
        } catch {
            guard generation == sessionGeneration else { return }
            aiLog.error("edit failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            overlayPhase = .error
            status = "Idle"
        }

        hideOverlay()
    }

    /// A hold shows the overlay only once Fn has been down for
    /// `tapThreshold`, so tapping Fn on its own never flashes it. The
    /// microphone starts on key-down regardless, so no words are lost.
    private func revealOverlay() {
        overlayRevealTask?.cancel()
        overlayRevealTask = nil
        guard let pressed = holdPressedAt else {
            hud.show(model: self)
            return
        }
        let wait = Self.tapThreshold - Date().timeIntervalSince(pressed)
        guard wait > 0 else {
            hud.show(model: self)
            return
        }
        overlayRevealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled, self.isRecording else { return }
            self.overlayRevealTask = nil
            self.hud.show(model: self)
        }
    }

    /// Ends a session started by tapping Fn: nothing is inserted, saved to
    /// history, or shown.
    private func discardTap() async {
        shortcutLog.notice("Fn tapped, not held -> session discarded")
        discardOnStop = false
        holdPressedAt = nil
        overlayRevealTask?.cancel()
        overlayRevealTask = nil
        shortcutSession.sessionDidStopExternally()
        sessionGeneration &+= 1
        await engine.cancel()
        isRecording = false
        finalizedText = ""
        volatileText = ""
        cleanedText = ""
        pendingSelection = nil
        pendingContext = nil
        isEditSession = false
        isGenerateSession = false
        recordingStartedAt = nil
        status = "Idle"
        hud.hide()
    }

    private func hideOverlay() {
        guard !isRecording else { return }
        hud.hide()
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
        case .off:
            // Replacements are the user's own mapping, not a cleanup guess, so
            // they still apply when the rule pass is switched off.
            let replaced = RuleCleaner.applyReplacements(rawText, wordReplacements)
            return withMentions(RuleCleaner.applySpokenFormatting(replaced, profile: activeProfile))
        case .rules:
            return withMentions(RuleCleaner.clean(rawText, replacements: wordReplacements, profile: activeProfile))
        }
    }

    func refreshCleaned() {
        cleanedText = cleanedTextForCurrentMode()
    }

    /// In chat apps with @-mentions, "at Priya" becomes "@Priya", which Slack
    /// turns into a real mention when pasted. Messages has no @-mentions.
    private func withMentions(_ text: String) -> String {
        guard activeProfile == .chat,
              targetApp?.bundleIdentifier != "com.apple.MobileSMS" else { return text }
        return Mentions.apply(to: text, names: mentionNames)
    }

    // MARK: - Context

    private func resolveContextProfile(for app: NSRunningApplication?) {
        if let forced = contextMode.profile {
            activeProfile = forced
            activeProfileWasDetected = false
        } else {
            activeProfile = ContextDetector.detect(for: app)
            activeProfileWasDetected = true
        }
        hasContext = true
        contextLog.notice("""
        context: mode=\(self.contextMode.rawValue, privacy: .public) \
        profile=\(self.activeProfile.rawValue, privacy: .public) \
        detected=\(self.activeProfileWasDetected, privacy: .public) \
        app=\(app?.bundleIdentifier ?? "nil", privacy: .public)
        """)
    }

    var contextStatus: String {
        guard contextMode == .auto else {
            return "Every dictation uses \(contextMode.profile?.label ?? "Generic")."
        }
        guard hasContext else { return "Picks a profile from the frontmost app." }
        return "Auto \u{00b7} last dictation used \(activeProfile.label)."
    }

    func contextModeChanged() {
        if let forced = contextMode.profile {
            activeProfile = forced
            activeProfileWasDetected = false
            hasContext = true
        }
        persistPreferences()
        refreshCleaned()
    }

    func completeOnboarding() {
        onboardingCompleted = true
        persistPreferences()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.presentLicenseGateIfNeeded()
        }
    }

    // MARK: - Licensing

    private var didStartLicensing = false
    private var didCheckLicenseGate = false

    func prepareLicensing() async {
        if !didStartLicensing {
            didStartLicensing = true
            license.beginPeriodicChecks()
        }
        guard !didCheckLicenseGate else { return }
        didCheckLicenseGate = true
        guard onboardingCompleted else { return }

        try? await Task.sleep(for: .seconds(2))
        presentLicenseGateIfNeeded()
    }

    func presentLicenseGateIfNeeded() {
        guard onboardingCompleted,
              license.isConfigured,
              !license.canUseApp else { return }
        LicenseWindowController.shared.present(model: self)
    }

    // MARK: - AI settings

    @discardableResult
    func saveAIKey(_ key: String) -> Bool {
        guard aiProvider.usesEndpoint else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let saved = AIKeychain.save(trimmed, for: aiProvider)
        refreshAIKeyState()
        return saved
    }

    func removeAIKey() {
        AIKeychain.delete(for: aiProvider)
        refreshAIKeyState()
    }

    func selectAIProvider(_ provider: AIProvider) {
        guard provider != aiProvider else { return }
        if aiProvider.usesEndpoint {
            aiProviderConfigs[aiProvider.rawValue] = AIProviderConfig(
                endpoint: aiEndpoint,
                model: aiModel
            )
        }
        aiTranscriptionModels[aiProvider.rawValue] = aiTranscriptionModel

        aiProvider = provider

        if provider.usesEndpoint {
            let saved = aiProviderConfigs[provider.rawValue]
            aiEndpoint = saved?.endpoint ?? provider.defaultEndpoint
            aiModel = saved?.model ?? provider.defaultModel
        }
        aiTranscriptionModel = aiTranscriptionModels[provider.rawValue]
            ?? provider.defaultTranscriptionModel

        refreshAIKeyState()
        persistPreferences()
    }

    private func refreshAIKeyState() {
        aiKeyConfigured = aiProvider.usesEndpoint && AIKeychain.hasKey(for: aiProvider)
    }

    func testAIConnection() async -> String {
        guard let configuration = aiConfiguration else {
            if aiProvider == .apple { return AIService.appleIntelligenceAvailabilityDescription }
            return "Add an endpoint, model, and key first."
        }
        do {
            let reply = try await AIService.test(configuration: configuration)
            if configuration.provider == .apple {
                return "Connected to Apple Intelligence: \(reply)"
            }
            return "Connected to \(configuration.model): \(reply)"
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Personalization

    func addVocabulary(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !customVocabulary.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        customVocabulary.append(trimmed)
        persistPreferences()
    }

    func removeVocabulary(_ word: String) {
        customVocabulary.removeAll { $0 == word }
        learnedVocabulary.remove(word)
        persistPreferences()
    }

    @discardableResult
    func addReplacement(heard: String, replacement: String) -> Bool {
        let value = WordReplacement(heard: heard, replacement: replacement)
        guard value.isUsable else { return false }
        wordReplacements.append(value)
        persistPreferences()
        refreshCleaned()
        return true
    }

    func removeReplacement(_ id: UUID) {
        wordReplacements.removeAll { $0.id == id }
        persistPreferences()
        refreshCleaned()
    }

    func personalizationChanged() {
        persistPreferences()
        refreshCleaned()
    }

    // MARK: - Learning

    /// Languages written with spaces between words. The term and correction
    /// matching splits on them.
    private var learningSupported: Bool {
        language != .japanese && language != .chineseSimplified
    }

    private func isKnownWord(_ word: String) -> Bool {
        SpellingDictionary.knows(word, language: language.transcriptionCode)
    }

    /// Names from the screen that aren't already in the vocabulary. They are
    /// hints for the on-device recognizer only and are never sent to a
    /// transcription provider.
    private func screenTerms(from text: String?) -> [String] {
        guard let text, learningSupported else { return [] }
        let known = Set(customVocabulary.map { $0.lowercased() })
        let terms = ScreenTerms.extract(from: text, isKnownWord: isKnownWord)
            .filter { !known.contains($0.lowercased()) }
        if !terms.isEmpty {
            contextLog.notice("screen terms: \(terms.count, privacy: .public)")
        }
        return terms
    }

    private func watchForCorrections(of inserted: String) {
        guard learnFromCorrections, learningSupported, !activeProfile.isCodeLike,
              let pid = targetApp?.processIdentifier,
              !inserted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        correctionWatcher.begin(inserted: inserted, pid: pid)
    }

    private func correctionsObserved(inserted: String, edited: String) {
        guard learnFromCorrections else { return }
        let corrections = CorrectionDetector.corrections(original: inserted, edited: edited, isKnownWord: isKnownWord)
        guard !corrections.isEmpty else { return }

        var learned: [String] = []
        for correction in corrections {
            let outcome = correctionTally.record(correction)
            learned += learn(correction, outcome)
        }
        contextLog.notice("corrections: seen=\(corrections.count, privacy: .public) learned=\(learned.count, privacy: .public)")
        persistPreferences()
        if !learned.isEmpty {
            refreshCleaned()
            showLearningNotice(learned.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", "))
        }
    }

    /// Adds what the tally says is ready: terms to vocabulary, and a
    /// replacement when the misheard form is safe to rewrite. Returns what is
    /// new, for the notice.
    private func learn(_ correction: Correction, _ outcome: CorrectionTally.Outcome) -> [String] {
        var learned: [String] = []
        for term in outcome.terms
        where !customVocabulary.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) {
            customVocabulary.append(term)
            learnedVocabulary.insert(term)
            learned.append(term)
        }
        if outcome.replacement,
           !wordReplacements.contains(where: { $0.heard.caseInsensitiveCompare(correction.heard) == .orderedSame }) {
            wordReplacements.append(WordReplacement(heard: correction.heard, replacement: correction.corrected, learned: true))
            if learned.isEmpty { learned.append(correction.corrected) }
        }
        return learned
    }

    private func showLearningNotice(_ terms: String) {
        // Mid-dictation the overlay is busy; the words are learned regardless.
        guard !isRecording, !isStartingDictation, overlayPhase != .processing else { return }
        let notice = "Learned \(terms)"
        learningNotice = notice
        hud.show(model: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.learningNotice == notice, !self.isRecording else { return }
            self.hud.hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if self.learningNotice == notice { self.learningNotice = nil }
            }
        }
    }

    // MARK: - Cleanup capture

    /// Temporary debugging aid: appends each dictation, raw and cleaned, to a
    /// local file so the cleanup rules can be reviewed against real speech.
    /// Off by default, and the file never leaves this Mac.
    static var captureFileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("QuietSpeech/dictation-capture.jsonl")
    }

    /// The capture file stops growing here; delete it to start a new one.
    private static let captureFileLimit = 5_000_000

    private func captureDictation(raw: String, cleaned: String, kind: String = "dictation") {
        guard captureDictations, Self.developerToolsEnabled else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: Self.captureFileURL.path)[.size] as? Int) ?? 0
        guard size < Self.captureFileLimit else { return }

        let entry: [String: String] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "app": targetApp?.localizedName ?? "",
            "kind": kind,
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
            + (size >= Self.captureFileLimit ? " \u{00b7} full, delete to restart" : "")
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

    // MARK: - Audio clips for the speech bench

    static var clipsDirectoryURL: URL {
        captureFileURL.deletingLastPathComponent().appendingPathComponent("speech-clips", isDirectory: true)
    }

    /// About 30 minutes of 16 kHz mono audio.
    private static let clipsLimit = 60_000_000

    private static func clipFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: clipsDirectoryURL, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
    }

    /// Copies the session's WAV next to a JSON file with what Apple heard,
    /// the hints it was given, and where it was dictated.
    private func saveClip(_ audioURL: URL) {
        let transcript = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        let manager = FileManager.default
        let directory = Self.clipsDirectoryURL
        let used = Self.clipFiles().reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard used < Self.clipsLimit else {
            clipStatus = "Clip folder is full; delete it to record more."
            return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let id = formatter.string(from: Date())
        let entry: [String: Any] = [
            "id": id,
            "at": ISO8601DateFormatter().string(from: Date()),
            "app": targetApp?.localizedName ?? "",
            "locale": language.rawValue,
            "language": language.transcriptionCode,
            "apple": transcript,
            "vocabulary": engine.contextualStrings,
        ]
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: audioURL, to: directory.appendingPathComponent("\(id).wav"))
            let data = try JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("\(id).json"))
        } catch {
            shortcutLog.error("saving clip failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshClipStatus()
    }

    func refreshClipStatus() {
        let files = Self.clipFiles()
        let count = files.filter { $0.pathExtension == "wav" }.count
        guard count > 0 else {
            clipStatus = "No clips yet."
            return
        }
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        clipStatus = "\(count) clip\(count == 1 ? "" : "s") \u{00b7} \(max(bytes / 1_000_000, 1)) MB"
    }

    func revealClips() {
        let directory = Self.clipsDirectoryURL
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func clearClips() {
        try? FileManager.default.removeItem(at: Self.clipsDirectoryURL)
        refreshClipStatus()
    }

    var clipsExist: Bool {
        FileManager.default.fileExists(atPath: Self.clipsDirectoryURL.path)
    }

    // MARK: - History

    static var historyFileURL: URL {
        captureFileURL.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    private static let historyLimit = 200

    private func recordHistory(raw: String, cleaned: String) {
        guard historyEnabled else { return }
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        history.insert(
            DictationRecord(
                date: Date(),
                appName: targetApp?.localizedName ?? "Unknown app",
                text: trimmed,
                raw: raw.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            at: 0
        )
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        saveHistory()
    }

    func copyHistory(_ record: DictationRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.text, forType: .string)
    }

    func deleteHistory(_ record: DictationRecord) {
        history.removeAll { $0.id == record.id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func historySettingChanged() {
        persistPreferences()
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(history) else { return }

        let url = Self.historyFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func loadHistory() -> [DictationRecord] {
        guard let data = try? Data(contentsOf: historyFileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DictationRecord].self, from: data)) ?? []
    }

    // MARK: - Insertion

    func insertText() {
        insertIntoFrontmostApp(target: targetApp)
    }

    /// Re-types the last dictation into whatever app is frontmost now, for the
    /// Paste Again binding.
    func pasteAgain() {
        guard license.canUseApp else {
            presentLicenseGateIfNeeded()
            return
        }
        guard !lastInsertedText.isEmpty else { return }
        insertIntoFrontmostApp(target: NSWorkspace.shared.frontmostApplication)
    }

    private func insertIntoFrontmostApp(target: NSRunningApplication?) {
        let text = cleanedText.isEmpty ? rawText : cleanedText
        insertText(text, target: target)
    }

    private func insertText(_ text: String, target: NSRunningApplication?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        guard Permissions.accessibilityGranted else {
            accessibilityGranted = false
            errorMessage = "Text is ready, but Accessibility permission is needed to type it into other apps."
            return
        }

        lastInsertedText = text
        // Synthetic Unicode key events don't produce Return, so text with
        // paragraph breaks or bullets must go through AX or the clipboard.
        let isMultiline = text.contains("\n")

        let destination = target ?? NSWorkspace.shared.frontmostApplication

        // Hand focus back only when the target isn't already frontmost. Calling
        // activate() on an already-frontmost app can make a browser re-focus its
        // AXWebArea and drop the caret out of a web editor.
        if let destination, destination != NSRunningApplication.current,
           NSWorkspace.shared.frontmostApplication != destination {
            destination.activate(options: [])
        }

        // Rich web/Electron/Notes editors accept ⌘V far more reliably than AX
        // writes or synthesized Unicode key events. Chrome in particular often
        // exposes the focused node as an unfocused AXWebArea, and both Chrome
        // and Slack acknowledge AX writes they silently drop — so an AX
        // success is not proof the text landed. Paste first there, then fall
        // back to direct insertion.
        let pasteReason = useDirectInsertion ? Self.pasteReason(for: destination) : nil
        let preferPaste = pasteReason != nil
        insertLog.notice("insertion policy: app=\(destination?.bundleIdentifier ?? "nil", privacy: .public) preferPaste=\(preferPaste ? "yes" : "no", privacy: .public) reason=\(pasteReason ?? "direct", privacy: .public)")
        if preferPaste {
            if PasteService.insert(text) {
                insertLog.notice("insertion path: clipboard paste (web/rich text)")
                return
            }
            insertLog.notice("clipboard paste declined; falling back to direct insertion")
        }

        // Three-tier insertion, cheapest and cleanest first:
        //   1. Accessibility write — no clipboard, instant.
        //   2. Synthetic typing — no clipboard, works where AX can't.
        //   3. Paste — borrows the clipboard, so last resort.
        if useDirectInsertion {
            // Electron editors (VS Code, Cursor, Windsurf) expose an empty
            // hidden textarea unless a screen reader is running. AX writes to
            // it report success and are dropped, so type there instead.
            let skipAX = destination.map(Self.isElectron) ?? false
            if !skipAX, AXInsertService.insert(text) {
                insertLog.notice("insertion path: accessibility")
                return
            }
            if !isMultiline, TypingService.type(text) {
                insertLog.notice("insertion path: synthetic typing")
                return
            }
        }

        if !preferPaste, PasteService.insert(text) {
            insertLog.notice("insertion path: clipboard paste")
        } else {
            errorMessage = "Could not insert text. Check Accessibility permission."
        }
    }

    /// Why ⌘V is the safer first move for this app, or `nil` for direct
    /// insertion. Web and Electron editors are the cases where AX reports
    /// success for writes it does not apply, so the direct path can't tell
    /// failure from success. Chrome PWAs still report a `com.google.Chrome*`
    /// bundle id.
    private static func pasteReason(for app: NSRunningApplication?) -> String? {
        guard let app, let id = app.bundleIdentifier else { return nil }
        if id == "com.apple.Notes" { return "notes" }
        let browserPrefixes = [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera",
        ]
        if browserPrefixes.contains(where: { id.hasPrefix($0) }) { return "browser" }
        if id == "com.tinyspeck.slackmacgap" { return "slack" }
        // Other Electron apps have the same silent-drop bridge. Editors and
        // terminals are exempt: their text surfaces accept direct insertion
        // reliably, and the no-clipboard path is worth keeping there.
        guard !directTypingApps.contains(id), isElectron(app) else { return nil }
        return "electron"
    }

    /// Apps that are Electron-based but where synthetic typing has proven
    /// reliable, and where avoiding the clipboard matters most. Their AX writes
    /// are not: see `insertText`.
    private static let directTypingApps: Set<String> = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf",
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

    // MARK: - Activation

    private func wireShortcuts() {
        shortcuts.onEvent = { [weak self] event, at in
            self?.handleShortcutEvent(event, at: at)
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
        correctionWatcher.onEdited = { [weak self] inserted, edited in
            self?.correctionsObserved(inserted: inserted, edited: edited)
        }
        AXInsertService.onUnverifiedInsert = { [weak self] in
            self?.errorMessage = "Text may not have reached the app — it's in the transcript above if you need Copy."
        }
    }

    private func handleShortcutEvent(_ event: ShortcutEvent, at time: Date) {
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
                holdPressedAt = mode == .hold ? time : nil
                discardOnStop = false
                beginDictation()
            case .stop:
                shortcutLog.notice("dictation stop")
                if let pressed = holdPressedAt, time.timeIntervalSince(pressed) < Self.tapThreshold {
                    // If the engine is still starting, start() sees the
                    // session has ended and calls stop(), which discards.
                    discardOnStop = true
                }
                Task { await self.stop() }
            case .switchedToToggle:
                // Fn was being held and Cmd just joined it. The recording and
                // the audio keep running; only the way it ends has changed.
                shortcutLog.notice("latched into toggle mode")
                holdPressedAt = nil
                if isRecording { revealOverlay() }
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
        defaults.set(saveAudioClips, forKey: "saveAudioClips")
        defaults.set(onboardingCompleted, forKey: "onboardingCompleted")
        defaults.set(cleanMode.rawValue, forKey: "cleanMode")
        defaults.set(language.rawValue, forKey: "language")
        defaults.set(customVocabulary, forKey: "customVocabulary")
        if let data = try? JSONEncoder().encode(wordReplacements) {
            defaults.set(data, forKey: "wordReplacements")
        }
        defaults.set(learnFromScreen, forKey: "learnFromScreen")
        defaults.set(learnFromCorrections, forKey: "learnFromCorrections")
        defaults.set(Array(learnedVocabulary), forKey: "learnedVocabulary")
        if let data = try? JSONEncoder().encode(correctionTally) {
            defaults.set(data, forKey: "correctionTally")
        }
        defaults.set(historyEnabled, forKey: "historyEnabled")
        defaults.set(contextMode.rawValue, forKey: "contextMode")
        if aiProvider.usesEndpoint {
            aiProviderConfigs[aiProvider.rawValue] = AIProviderConfig(
                endpoint: aiEndpoint,
                model: aiModel
            )
        }
        if let data = try? JSONEncoder().encode(aiProviderConfigs) {
            defaults.set(data, forKey: "aiProviderConfigs")
        }
        defaults.set(aiProvider.rawValue, forKey: "aiProvider")
        defaults.set(aiEnabled, forKey: "aiEnabled")
        defaults.set(aiPolishEnabled, forKey: "aiPolishEnabled")
        defaults.set(aiGenerateEnabled, forKey: "aiGenerateEnabled")
        defaults.set(aiGenerateTrigger, forKey: "aiGenerateTrigger")
        defaults.set(aiTranscriptionEnabled, forKey: "aiTranscriptionEnabled")
        aiTranscriptionModels[aiProvider.rawValue] = aiTranscriptionModel
        defaults.set(aiTranscriptionModels, forKey: "aiTranscriptionModels")
        defaults.set(aiEndpoint, forKey: "aiEndpoint")
        defaults.set(aiModel, forKey: "aiModel")
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
        saveAudioClips = defaults.bool(forKey: "saveAudioClips")
        if defaults.object(forKey: "onboardingCompleted") != nil {
            onboardingCompleted = defaults.bool(forKey: "onboardingCompleted")
        }
        if let raw = defaults.string(forKey: "cleanMode"), let value = CleanMode(rawValue: raw) {
            cleanMode = value
        }
        if let raw = defaults.string(forKey: "language"), let value = Language(rawValue: raw) {
            language = value
        }
        if let vocabulary = defaults.stringArray(forKey: "customVocabulary") {
            customVocabulary = vocabulary
        }
        if let data = defaults.data(forKey: "wordReplacements"),
           let value = try? JSONDecoder().decode([WordReplacement].self, from: data) {
            wordReplacements = value
        }
        if defaults.object(forKey: "learnFromScreen") != nil {
            learnFromScreen = defaults.bool(forKey: "learnFromScreen")
        }
        if defaults.object(forKey: "learnFromCorrections") != nil {
            learnFromCorrections = defaults.bool(forKey: "learnFromCorrections")
        }
        if let learned = defaults.stringArray(forKey: "learnedVocabulary") {
            learnedVocabulary = Set(learned)
        }
        if let data = defaults.data(forKey: "correctionTally"),
           let value = try? JSONDecoder().decode(CorrectionTally.self, from: data) {
            correctionTally = value
        }
        if defaults.object(forKey: "historyEnabled") != nil {
            historyEnabled = defaults.bool(forKey: "historyEnabled")
        }
        if let raw = defaults.string(forKey: "contextMode"), let value = ContextMode(rawValue: raw) {
            contextMode = value
        }
        if let raw = defaults.string(forKey: "aiProvider"),
           let value = AIProvider(rawValue: raw) {
            aiProvider = value
        } else {
            aiProvider = Self.inferAIProvider(defaults: defaults)
        }
        if defaults.object(forKey: "aiEnabled") != nil {
            aiEnabled = defaults.bool(forKey: "aiEnabled")
        }
        if defaults.object(forKey: "aiPolishEnabled") != nil {
            aiPolishEnabled = defaults.bool(forKey: "aiPolishEnabled")
        }
        if defaults.object(forKey: "aiGenerateEnabled") != nil {
            aiGenerateEnabled = defaults.bool(forKey: "aiGenerateEnabled")
        } else {
            aiGenerateEnabled = aiEnabled || aiPolishEnabled
            defaults.set(aiGenerateEnabled, forKey: "aiGenerateEnabled")
        }
        if let value = defaults.string(forKey: "aiGenerateTrigger"),
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            aiGenerateTrigger = value
        }
        if defaults.object(forKey: "aiTranscriptionEnabled") != nil {
            aiTranscriptionEnabled = defaults.bool(forKey: "aiTranscriptionEnabled")
        }
        if let saved = defaults.dictionary(forKey: "aiTranscriptionModels") as? [String: String] {
            aiTranscriptionModels = saved
        }
        aiTranscriptionModel = aiTranscriptionModels[aiProvider.rawValue]
            ?? aiProvider.defaultTranscriptionModel
        if let value = defaults.string(forKey: "aiEndpoint"), !value.isEmpty {
            aiEndpoint = value
        }
        if let value = defaults.string(forKey: "aiModel"), !value.isEmpty {
            aiModel = value
        }
        if let data = defaults.data(forKey: "aiProviderConfigs"),
           let value = try? JSONDecoder().decode([String: AIProviderConfig].self, from: data) {
            aiProviderConfigs = value
        }
        if aiProvider.usesEndpoint {
            let saved = aiProviderConfigs[aiProvider.rawValue]
            if let saved {
                aiEndpoint = saved.endpoint
                aiModel = saved.model
            } else {
                aiProviderConfigs[aiProvider.rawValue] = AIProviderConfig(
                    endpoint: aiEndpoint,
                    model: aiModel
                )
            }
        }
    }

    private static func generateInstruction(from text: String, trigger: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let triggerWord = trigger
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init)?
            .lowercased()
        guard let triggerWord, !triggerWord.isEmpty else { return nil }

        let end = trimmed.firstIndex(where: { $0.isWhitespace || $0.isPunctuation }) ?? trimmed.endIndex
        let firstWord = String(trimmed[..<end]).lowercased()
        guard firstWord == triggerWord else { return nil }

        return String(trimmed[end...])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func inferAIProvider(defaults: UserDefaults) -> AIProvider {
        let endpoint = defaults.string(forKey: "aiEndpoint") ?? ""
        if AIService.isLocalEndpoint(endpoint) { return .ollama }
        let lowered = endpoint.lowercased()
        if lowered.contains("groq") { return .groq }
        if lowered.contains("openai.com") { return .openAI }
        if !endpoint.isEmpty { return .custom }
        return AIKeychain.hasLegacyKey() ? .openAI : .apple
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
        sessionGeneration &+= 1
        isEditSession = false
        aiProcessing = nil

        let previousPhase = overlayPhase
        // Give the preview a real icon to show, so it matches a live session.
        targetApp = NSWorkspace.shared.frontmostApplication
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
            // Then the states that follow a real dictation.
            guard let self, !Task.isCancelled else { return }
            self.overlayPhase = .processing
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            self.overlayPhase = .done
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
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
        sessionGeneration &+= 1
        isEditSession = false
        pendingSelection = nil
        aiProcessing = nil
        recordingStartedAt = nil
    }
}
