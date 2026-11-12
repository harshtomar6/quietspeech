# QuietSpeech — decision log

Repository review: 2026-10-26. Existing commits establish the actions below. Their original rationale was not recorded in this repository, so it is left open rather than invented.

## 2026-10-25 — Rename to QuietSpeech and publish 0.1

- **Recorded action:** The project was renamed from Whispr Proto to QuietSpeech, and 0.1 was published with a landing page.
- **Why:** Not recorded here; ask the owner before describing the brand decision.
- **Evidence:** Commit `5f159b8`.

## 2026-10-25 — Add landing-page measurement

- **Recorded action:** Minilytics and goal tracking were added to the landing page.
- **Why:** Not recorded here.
- **Evidence:** Commit `abe04aa`; current [site source](../landing/index.html).

## 2026-10-25 — Publish 0.2

- **Recorded action:** Version 0.2 was added to the site and Sparkle appcast after work on correction learning and AI polish.
- **Why:** Not recorded here.
- **Evidence:** Commits `6a2e36a` and `574e78b`; [appcast](../landing/appcast.xml).

## 2026-10-26 — Focus the initial audience on subscription-averse Mac users

- **Decision:** Prioritize Mac users who want dictation without a monthly payment. Lead with fast, easy, private dictation and no recurring subscription; treat editing and generation as supporting capabilities.
- **Why:** The owner identified avoiding monthly dictation-app costs as the primary customer motivation.
- **Status:** The owner confirmed that QuietSpeech has just launched and has no active marketing campaigns yet.
- **Evidence:** Owner confirmation in the project-memory setup conversation on 2026-10-26. No customer research or comparative speed measurement is recorded here.

## 2026-10-26 — Use one MCP endpoint for memory and task tracking

- **Decision:** Keep QuietSpeech's reviewed Markdown in this repository. Serve it with read-only `memory:read` tools alongside Missions task tools (`pm` scope) at `https://harshtomar.com/api/mcp/mcp`.
- **Why:** Agents need current product context and a place to create and update project tasks through one connector.
- **Status:** A QuietSpeech Missions project is linked to `harshtomar6/quietspeech`. The previous standalone Cloudflare memory endpoint returns HTTP 410 with the replacement URL.
- **Evidence:** [Unified MCP implementation](https://github.com/harshtomar6/harshtomar/tree/main/src/lib/mcp), [Missions](https://harshtomar.com/admin/missions), and the live OAuth/tool smoke test on 2026-10-26.

## 2026-11-09 — Offer double-tap or a separate shortcut for hands-free dictation

- **Decision:** Give Tap to Toggle two activation choices: double-tap the current Hold to Talk key, or record a separate shortcut. In double-tap mode, a single tap stops hands-free dictation and holding still supports push-to-talk. Keep existing installations on their separate shortcut and remember it when switching modes.
- **Why:** The owner requested both choices. Distinguishing a tap from a sustained hold before starting avoids launching and canceling microphone sessions for the two taps. Timing and implemented behavior are recorded in [product](product.md#personalization-and-output).
- **Evidence:** Owner request in this conversation; [session controller](../Sources/QuietSpeech/ShortcutCore/DictationShortcutSessionController.swift), [settings](../Sources/QuietSpeech/ToggleActivationSettings.swift), and [tests](../Tests/QuietSpeechTests/ToggleActivationTests.swift). Published in 0.3.4 on 2026-11-09; see the [Sparkle feed](../landing/appcast.xml).


## 2026-11-12 — Pause current media at dictation startup

- **Decision:** Add an enabled-by-default, persistent Activation setting that sends a pause-only command before microphone startup. Initially leave media paused afterward; this part is superseded by the automatic-resume decision below. Apply it to hold, toggle and menu starts through the shared startup path.
- **Why:** The owner requested automatically pausing playing media when dictation is activated. Avoid a play/pause key event, which can start paused media. Bound the request to 150 ms and continue dictation if unavailable.
- **Implementation and limits:** Dynamically resolve the private system MediaRemote pause sender; missing symbols are a no-op. It targets macOS’s current media player, so unsupported players or simultaneous sources are not guaranteed. No metadata lookup, Automation prompt or additional dependency is introduced. See [media controller](../Sources/QuietSpeech/MediaPlaybackController.swift) and [tests](../Tests/QuietSpeechTests/MediaPlaybackControllerTests.swift).
- **Revisit:** If macOS changes this private API or live player compatibility fails, revise the sender while retaining pause-only behavior and responsive startup. No public release is claimed by this entry.

## 2026-11-12 — Resume interrupted media after transcription finishes

- **Decision:** Extend the pause setting to resume the same paused media app after the complete transcription/AI/insertion flow. The owner explicitly requested automatic resume, superseding the earlier pause-only choice. Keep its existing enabled-by-default preference.
- **Resume conditions:** Capture a confirmed playing state and player process ID before Pause. Send Play only if that app is still selected and paused at completion. Unknown state, an initially paused player, an unsuccessful Pause or a changed app does not authorize Play. Track changes within the same app are not identified. Carry pause ownership to a newer dictation and ignore stale completion requests.
- **Implementation:** Commands retain the runtime-resolved MediaRemote sender. Direct C playback-state queries returned an empty player ID in a signed executable on this Mac; a read-only JavaScript query through the macOS script host returned the correct identity and state in the live test. The helper returns only PID and state, has a bounded lifetime, and does not request Automation or capture audio. Unavailable reads degrade to pause-only. See [controller](../Sources/QuietSpeech/MediaPlaybackController.swift), [completion paths](../Sources/QuietSpeech/AppModel.swift) and [tests](../Tests/QuietSpeechTests/MediaPlaybackControllerTests.swift).
- **Revisit:** macOS changes to these private media interfaces or live compatibility failures. No public release is claimed by this entry.

## 2026-11-12 — Put available updates first in the menu bar

- **Decision:** Show an update dot on QuietSpeech’s menu-bar icon and place “Install New Update…” before dictation controls whenever Sparkle reports an installable update. Route that action through Sparkle’s existing installation UI and use gentle menu reminders for scheduled checks. Keep manual Check for Updates when no update is known.
- **Why:** The owner explicitly requested the dot and first-position install action. Sparkle remains responsible for compatibility, download verification and installation; no separate feed poller is added.
- **Lifecycle:** Keep the reminder after dismissal or while downloading, clear it on explicit Skip or a confirmed no-update result, and persist it for the current build so a relaunch does not lose it. A newer installed build starts without the older reminder. Render the dot as a template mask so it follows menu-bar and recording tint.
- **Evidence:** [controller](../Sources/QuietSpeech/UpdateController.swift), [menu](../Sources/QuietSpeech/QuietSpeechApp.swift) and [tests](../Tests/QuietSpeechTests/UpdateControllerTests.swift). A separate signed test app detected the published update and displayed the badged icon with the install action first. No public version change is claimed.

## 2026-11-12 — Prefer ordinary input delivery when shortcuts are interrupted

- **Decision:** Make the synchronous event callback fail open: never wait for the configuration lock, never repeatedly re-enable a timeout/user-disabled stream, and invalidate stale queued activations. Pause unhealthy listeners until an explicit retry and discard uncertain recordings. Expose recovery through Restore Shortcuts → Permissions.
- **Why:** Investigation reproduced stale Fn state consuming ordinary Command, a callback blocked behind a held lock, and an activation delivered after disable. These demonstrate input-handling weaknesses; they do not prove the cause of the complete reported keyboard-and-mouse incident.
- **Lifecycle and generated events:** Disable new ports until their run-loop source is installed, serialize startup against cancellation, and release the old listener before relaunch. Use private event sources with zero hardware suppression, explicit hardware passthrough and a marker the shortcut listener ignores. Keep permission checks, UI work and per-key logs out of the input callback.
- **Evidence and remaining limits:** [Investigation](investigations/input-freeze.md) and [thirteen safety tests](../Tests/QuietSpeechTests/ShortcutBackendSafetyTests.swift). Exact customer permission/hardware reproduction and full single-instance enforcement remain separate work. No public release is claimed here.

## 2026-11-12 — Remember a microphone choice without changing system audio

- **Decision:** Offer the same microphone picker in onboarding and Transcription settings, with System Default plus connected input devices. Save an explicit choice by Core Audio UID and route only QuietSpeech's engine. Preserve a disconnected selection and require reconnection or an explicit new choice instead of falling back silently.
- **Why:** The owner requested microphone input selection after a report that an external microphone could not be selected. A visible, bounded level test helps confirm setup without dictating into another app or retaining audio. Pairing/connection remains a macOS task, with a link to Sound settings.
- **Capture lifecycle:** Use a fresh engine for each recording/test so formats are not cached across devices. Stop the 15-second test before dictation or when leaving the picker. Discard an interrupted dictation when its actual input stops or changes; ignore configuration notifications if the engine, input device and format are still valid. Signed capture checks showed that normal startup itself can emit such notifications.
- **Evidence and limits:** [Routing and preview](../Sources/QuietSpeech/MicrophoneController.swift), [shared UI](../Sources/QuietSpeech/MicrophoneSettings.swift) and [tests](../Tests/QuietSpeechTests/MicrophoneControllerTests.swift). Built-in and connected iPhone capture were exercised in a signed probe without changing the system default. Other external hardware and physical disconnect behavior still need live coverage. No public release is claimed.

## Future entries

Add an entry when a decision changes product behavior, audience focus, positioning, pricing, architecture, or a major marketing direction. Record the decision, reason, alternatives, evidence, owner, date, and what would cause a revisit. If superseded, link the new decision instead of silently rewriting history.
