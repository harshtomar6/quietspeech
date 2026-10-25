# QuietSpeech

Dictate, edit, and generate text in any Mac app. On-device by default.

Hold <kbd>Fn</kbd>, speak, and let go. The cleaned-up text appears wherever your cursor is.

**[quietspeech.app](https://quietspeech.app)** has the notarized download and license keys.

## What it does

- **Dictate.** Apple's on-device recognizer transcribes while you hold the key, and an overlay shows the live transcript. Filler words, false starts and missing punctuation are cleaned up before the text is inserted.
- **Edit.** Select some text, hold the key, and say what to change ("make it shorter"). The selection is rewritten in place.
- **Generate.** Say "generate" and then what you need. A draft is written and inserted where you're working.
- **Works in code.** In editors and terminals, AI polish is skipped, spoken flags like "dash dash watch" become `--watch`, and command names stay lowercase.
- **Vocabulary.** Add names and jargon so the recognizer gets them right.

## Privacy

Audio is transcribed on this Mac, and Apple Intelligence cleans up the text on this Mac. There's no account and no telemetry, and audio isn't kept after transcription. The text of your last 200 dictations is saved locally as history.

You can connect OpenAI, Groq, Ollama, or a custom endpoint instead. When you do, only what you send goes to that provider.

## Requirements

- macOS 26 or later
- An Apple silicon Mac
- Microphone and Accessibility permissions
- Apple Intelligence turned on for AI cleanup, editing and generating. Without it, dictation still works and rules-based cleanup takes over.

## Building from source

You need macOS 26 and Xcode 26 or later.

```sh
./build-app.sh            # release build, assembled into QuietSpeech.app
open QuietSpeech.app
swift test                # unit tests
```

`build-app.sh` signs with a Developer ID or Apple Development certificate if you have one. Without one it signs ad-hoc, and macOS then asks for permissions again after every rebuild.

`package.sh` makes a distributable build. It signs, notarizes and staples the app, packages it as a DMG, and updates the Sparkle feed. This needs a Developer ID certificate and a `notarytool` keychain profile; the script explains how to set one up.

## Project layout

| Path | Contents |
|---|---|
| `Sources/QuietSpeech/` | The menu-bar app: speech, cleanup, AI, text insertion, settings, overlay |
| `Sources/Licensing/` | License activation and validation, with tests in `Tests/LicensingTests/` |
| `landing/` | The quietspeech.app website and the Sparkle `appcast.xml` |
| `design/` | Design system, tokens and overlay concepts |
| `scripts/` | Build helpers, and `polish-bench/`, which scores AI polish on your captured dictations |

## License

QuietSpeech is free software under the [GNU General Public License v3](LICENSE). See [NOTICE](NOTICE) and [THIRD_PARTY_NOTICES](Resources/THIRD_PARTY_NOTICES.txt).

Copyright © 2026 Harsh Tomar.
