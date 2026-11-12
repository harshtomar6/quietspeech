# Input interruption investigation

Reviewed 2026-11-12. Baseline shortcut backend: commit `fab73bf` (unchanged from the published 0.3.6 backend). The customer incident’s exact app version, macOS version and changed permission are unknown. No customer identity or verbatim email is retained here.

## Conclusion and limits

The complete reported keyboard-and-mouse freeze has **not** been reproduced. Controlled, unposted-event replays reproduced stale modifier state, blocking callbacks and delivery of an activation after the event stream was disabled. The fixes address those concrete weaknesses; they are not proof of the cause of the customer’s external-display/peripheral incident.

## Confirmed findings

1. **Stale Fn after interruption.** The old processor remembered Fn across `tapDisabledByTimeout` / `tapDisabledByUserInput`, then immediately re-enabled the tap. If the release occurred during the gap, an ordinary Command press could match Fn+Command and be consumed. A replay of Fn-down, disabled-stream, missed Fn-up, Command-down reproduced this.
2. **Blocking callback.** The old processor waited on `NSLock.lock()` shared with configuration changes. Injected lock contention stalled the callback until the test released that lock. This demonstrates a failure mode, not a stall observed under normal production load. The callback now uses a nonblocking try and passes the event unchanged if matching cannot proceed immediately.
3. **Queued activation after disable.** A Fn activation queued for the main thread still arrived after the stream had been disabled. Generations now invalidate pending callbacks, and interruption resets the shortcut session and discards an active recording.
4. **Startup/cancellation race in the listener.** Code review found that the old worker could unconditionally enable a port after `stopTap()` ran before the worker published its run loop. New ports are immediately disabled until their source is installed; serialized startup/cancellation prevents late enable, and run-loop shutdown is queued so the stop cannot be missed before the loop begins. Lifecycle tests cover canceled and already-stopped startup. This race was not deliberately forced on a live global tap.
5. **Startup request origin.** The old async start inferred whether a shortcut requested it from mutable session state when the queued task eventually ran. A key release already handled on the main queue could erase that origin. The shortcut caller now captures the origin explicitly, and an ended shortcut request is rejected before startup. This finding is from code review; the backend’s stale queued-event behavior is separately covered by replay tests.
6. **Relaunch overlap.** The old process started its replacement before releasing its shortcut listener. Relaunch now stops the old listener first. General single-instance enforcement for independently launched copies is still separate work.

## Mouse input and generated events

The actual tap subscribes only to key-down, key-up and modifier changes; it does not intercept mouse clicks. The overlay is click-through. Neither fact proves that the app could not indirectly disrupt system responsiveness, but the matcher alone does not establish the cause of a complete mouse failure.

[Apple documents event-source defaults as allowing local hardware input](https://developer.apple.com/documentation/coregraphics/cgeventsource/localeventssuppressioninterval). Defaults were therefore **not** treated as proof that synthetic events caused the incident. As a defensive measure, our copy/paste and Unicode typing sources now use private event state, zero suppression interval, explicit mouse/keyboard/system-event passthrough, and an application marker. The shortcut processor ignores that marker, including events from another QuietSpeech process. Tests check these settings without posting any input.

## Recovery behavior

On a disabled-stream notification, the listener immediately passes events through. Outside the callback it checks the actual port state: macOS can queue a notification for our deliberate startup disable after the worker has already enabled the port. An already-enabled, still-authorized port clears its stale state without being re-enabled; a genuinely disabled port remains paused rather than repeatedly re-enabling. A main-queue permission monitor also stops it if Accessibility is revoked. Recovery is explicit through Restore Shortcuts → Permissions → Recheck; if macOS keeps stale trust state, Relaunch is available. No permission checks, UI calls, blocking locks or per-key logs run in the event callback.

## Validation

- Six replay tests failed against the old processor (seven failed assertions). These exercised stale keys, a held configuration lock, stop/disable handling and queued activation delivery. The mouse callback assertion is a defensive passthrough test; mouse events were not subscribed to by the original tap.
- The safety suite adds thirteen tests and uses only unposted events, injected lock contention, an injected denied-permission result and a pure lifecycle controller. It neither revokes the user’s real permission nor installs a global test tap.
- `swift test` passed all 100 tests; `./build-app.sh` produced a valid Developer ID signed app. The owner verified normal typing/clicks, a brief Fn tap and hold-to-dictate in the running candidate. macOS’s live tap list showed one enabled listener with keyboard-only mask 7168. Callback latency fields had no usable samples, so no latency measurement is claimed. No live permission-revocation or clamshell incident reproduction is claimed.

Evidence: [backend](../../Sources/QuietSpeech/ShortcutCore/ShortcutBackend.swift), [startup/session handling](../../Sources/QuietSpeech/AppModel.swift), [synthetic event source](../../Sources/QuietSpeech/KeyboardEventSource.swift), [safety tests](../../Tests/QuietSpeechTests/ShortcutBackendSafetyTests.swift).

## Remaining incident verification

Obtain the incident app/macOS versions, exact revoked permission, microphone connection type, external keyboard/mouse or receiver/dock connections, and an approximate incident time. Reproduce permission loss, relaunch and device reconnection on a matching clamshell/external-display setup before claiming the full incident resolved. The availability of the internal touchpad while external devices failed leaves a device/display-specific explanation open.
