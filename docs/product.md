# QuietSpeech — product truth

Repository review: 2026-10-26. “Implemented” means supported by repository code or documentation; it does not certify a live installation or external service.

## Core workflows

| Workflow | Current behavior | Evidence |
| --- | --- | --- |
| Dictate | Hold the configured shortcut (Fn by default), speak, and release. A live overlay shows transcription, and the finished text is inserted into the focused app. Tap to Toggle offers a separate shortcut or double-tapping the Hold to Talk key. | [README](../README.md), [shortcut models](../Sources/QuietSpeech/ShortcutCore/ShortcutModels.swift) |
| Edit selected text | Select text, speak an instruction such as “make it shorter,” and replace the selection with a rewrite. Requires an available AI provider. | [README](../README.md), [app model](../Sources/QuietSpeech/AppModel.swift) |
| Generate | Say “generate” followed by a request to insert a new draft. Requires an available AI provider. | [README](../README.md), [site](../landing/index.html) |
| Code and terminal dictation | Context detection applies code- or shell-friendly formatting and skips AI polish in these contexts. | [README](../README.md), [context profiles](../Sources/QuietSpeech/ContextProfile.swift) |
| Chat mentions | In chat apps (Slack, Discord, WhatsApp, Telegram; not Messages), “at Priya” becomes @Priya when the name is on screen or in the vocabulary and the “at” opens a sentence or clause or follows a cue such as “hey” or “cc”. “at sign X” and “at the rate X” always make a mention. Because the recognizer often hears “at” as “add” or “ad”, those count too, unless “add” is the verb (“Add Priya to the channel”). A detached “@ Priya” is joined to @Priya for known names. Verified live in Slack on 2026-10-27; the “add” handling is unit-tested only. | [mentions](../Sources/Learning/Mentions.swift), [app model](../Sources/QuietSpeech/AppModel.swift) |

## Personalization and output

- **Implemented locally, not yet published:** Settings › Activation offers “Pause media when dictation starts,” enabled by default and remembered across launches. Dictation sends a pause-only request to the macOS current media player before starting the microphone; disabled mode sends nothing, paused media is never toggled to play, and media is left paused afterward. This is best-effort for players supporting system media controls; it does not mute all audio or pause every simultaneous source. An unavailable or unresponsive service does not prevent dictation (150 ms response budget). See [media control](../Sources/QuietSpeech/MediaPlaybackController.swift), [startup and preferences](../Sources/QuietSpeech/AppModel.swift), [Activation settings](../Sources/QuietSpeech/SettingsPanes.swift) and [tests](../Tests/QuietSpeechTests/MediaPlaybackControllerTests.swift).
- **Implemented locally, not yet published:** Overlay window show/hide is synchronous so a previous fade-out cannot hide a new dictation. Starting dictation also cancels the Settings overlay preview before it can reset or hide the live session. The old hide/show race was reproduced with an AppKit panel regression test on 2026-11-12. See [overlay window](../Sources/QuietSpeech/HUD.swift), [app model](../Sources/QuietSpeech/AppModel.swift) and [regression tests](../Tests/QuietSpeechTests/HUDVisibilityTests.swift).
- **Published in 0.3.6:** The listening overlay joins the focused app’s workspace as well as its Space. This fixes an active dictation session appearing invisible in Notes and TextEdit. Window metadata confirmed the earlier overlay was off-screen; the owner verified the indicator and text insertion in both apps on 2026-11-10. See [overlay window](../Sources/QuietSpeech/HUD.swift) and the [release notes](releases/0.3.6.md).
- **Published in 0.3.5:** Fn+Command activation leaves ordinary Command-Tab, Command-Shift-Tab, Command-C and Command-Space available when Fn is not held. Unrelated modifiers also pass through while another dictation key is held. See [shortcut matching](../Sources/QuietSpeech/ShortcutCore/ShortcutMatcher.swift) and [regression tests](../Tests/QuietSpeechTests/ShortcutPassthroughTests.swift).
- **Published in 0.3.4:** Dictionary checks for screen vocabulary and correction learning use the asynchronous spell checker with a 200 ms response budget. If it is unavailable, dictation proceeds without optional screen hints and that correction is not learned. Startup rejects overlapping launch requests. See [dictionary checks](../Sources/QuietSpeech/LearningService.swift), [response deadline](../Sources/QuietSpeech/TimedCallback.swift), and [app model](../Sources/QuietSpeech/AppModel.swift).
- **Published in 0.3.4:** Settings › Activation and onboarding offer “Double-tap hold key” and “Different shortcut” for Tap to Toggle. Double-tap starts hands-free dictation and a single tap stops it. Two quick presses must be within 350 ms of the first release; an isolated quick tap does nothing. In this mode a sustained hold starts after 300 ms to distinguish it from a tap. Existing preferences keep their separate shortcut, which is remembered while double-tap is selected. See [session controller](../Sources/QuietSpeech/ShortcutCore/DictationShortcutSessionController.swift), [shared settings](../Sources/QuietSpeech/ToggleActivationSettings.swift), and [regression tests](../Tests/QuietSpeechTests/ToggleActivationTests.swift). Published on 2026-11-09; see the [Sparkle feed](../landing/appcast.xml).
- Users can add custom vocabulary and word replacements. The app can read names from the focused window and learn suitable corrections where the target field can be read. See [personalization settings](../Sources/QuietSpeech/SettingsPanes.swift) and [learning service](../Sources/QuietSpeech/LearningService.swift).
- Output tries Accessibility insertion, then synthetic typing, with a clipboard paste fallback in apps that need it. See [output settings](../Sources/QuietSpeech/SettingsPanes.swift).
- A local, optional text history keeps up to 200 finished dictations. It does not store audio. See [history code](../Sources/QuietSpeech/AppModel.swift) and [history settings](../Sources/QuietSpeech/SettingsPanes.swift).

## Processing and privacy

- Apple's recognizer transcribes on the Mac by default. Apple Intelligence can polish text locally; rules-based cleanup remains available when it is off. See [README](../README.md).
- Optional provider choices include OpenAI, Groq, Ollama, and a custom endpoint. When configured for provider transcription or AI text work, the selected content goes to that provider. See [provider options](../Sources/QuietSpeech/AIProvider.swift) and [privacy settings](../Sources/QuietSpeech/SettingsPanes.swift).
- The app has no account or app telemetry according to the README. The **website** has Minilytics page and goal tracking; keep those claims distinct. See [site source](../landing/index.html).
- The app normally does not retain audio after transcription. A developer-oriented “Save audio clips” setting can retain clips for speech benchmarking. See [privacy settings](../Sources/QuietSpeech/SettingsPanes.swift).

## Requirements and commercial behavior

- Apple silicon, macOS 26 or later, Microphone and Accessibility permissions. Apple Intelligence is needed for local AI polish, editing, and generation; basic dictation still works without it. See [README](../README.md).
- The publicly launched site presents a $29 one-time license for two Macs, no account, a 14-day refund, and a downloadable build, 0.3.6 since 2026-11-10. The owner confirmed launch and sales status on 2026-10-26. License checks have a configured 14-day offline grace period. See [site](../landing/index.html) and [license configuration](../Sources/Licensing/LicenseConfiguration.swift).
- Sparkle handles app updates through the site appcast. See [appcast](../landing/appcast.xml) and [update controller](../Sources/QuietSpeech/UpdateController.swift).

## Status and limits

- **Implemented in the repository:** the workflows above, settings, licensing, and release packaging.
- **External status:** the owner confirmed the product and $29 offer are live on 2026-10-26; this setup did not independently test the download or checkout.
- **Compatibility:** insertion can vary by target app; the app includes fallback paths rather than guaranteeing identical behavior in every field.
