# QuietSpeech — product truth

Repository review: 2026-10-26. “Implemented” means supported by repository code or documentation; it does not certify a live installation or external service.

## Core workflows

| Workflow | Current behavior | Evidence |
| --- | --- | --- |
| Dictate | Hold the configured shortcut (Fn by default), speak, and release. A live overlay shows transcription, and the finished text is inserted into the focused app. A tap-to-toggle shortcut can also be configured. | [README](../README.md), [shortcut models](../Sources/QuietSpeech/ShortcutCore/ShortcutModels.swift) |
| Edit selected text | Select text, speak an instruction such as “make it shorter,” and replace the selection with a rewrite. Requires an available AI provider. | [README](../README.md), [app model](../Sources/QuietSpeech/AppModel.swift) |
| Generate | Say “generate” followed by a request to insert a new draft. Requires an available AI provider. | [README](../README.md), [site](../landing/index.html) |
| Code and terminal dictation | Context detection applies code- or shell-friendly formatting and skips AI polish in these contexts. | [README](../README.md), [context profiles](../Sources/QuietSpeech/ContextProfile.swift) |
| Chat mentions | In chat apps (Slack, Discord, WhatsApp, Telegram; not Messages), “at Priya” becomes @Priya when the name is on screen or in the vocabulary and the “at” opens a sentence or clause or follows a cue such as “hey” or “cc”. “at sign X” and “at the rate X” always make a mention. Because the recognizer often hears “at” as “add” or “ad”, those count too, unless “add” is the verb (“Add Priya to the channel”). A detached “@ Priya” is joined to @Priya for known names. Verified live in Slack on 2026-10-27; the “add” handling is unit-tested only. | [mentions](../Sources/Learning/Mentions.swift), [app model](../Sources/QuietSpeech/AppModel.swift) |

## Personalization and output

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
- The publicly launched site presents a $29 one-time license for two Macs, no account, a 14-day refund, and a downloadable build, 0.3.3 since 2026-10-28. The owner confirmed launch and sales status on 2026-10-26. License checks have a configured 14-day offline grace period. See [site](../landing/index.html) and [license configuration](../Sources/Licensing/LicenseConfiguration.swift).
- Sparkle handles app updates through the site appcast. See [appcast](../landing/appcast.xml) and [update controller](../Sources/QuietSpeech/UpdateController.swift).

## Status and limits

- **Implemented in the repository:** the workflows above, settings, licensing, and release packaging.
- **External status:** the owner confirmed the product and $29 offer are live on 2026-10-26; this setup did not independently test the download or checkout.
- **Compatibility:** insertion can vary by target app; the app includes fallback paths rather than guaranteeing identical behavior in every field.
