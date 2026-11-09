import Foundation

// Derived from FreeFlow (https://github.com/zachlatta/freeflow),
// Sources/ShortcutCore/DictationShortcutSessionController.swift,
// Copyright (c) Zach Latta, MIT licensed.
//
// Holds the "am I dictating, and which mode got me here" decision so the
// matcher can stay a pure edge detector. The interesting case is the latch:
// Fn is held (`.holdActivated` → hold mode), then Cmd is added and the toggle
// binding lights up. That must read as `.switchedToToggle`, not as a stop
// followed by a start, so the recording and its audio never flicker. Both
// releases then arrive while the mode is already `.toggle` and are ignored;
// the next toggle press stops the session.

enum DictationShortcutAction: Equatable {
    case start(RecordingTriggerMode)
    case stop
    case switchedToToggle
}

struct DictationShortcutSessionController {
    static let holdThreshold: TimeInterval = 0.3
    static let doubleTapInterval: TimeInterval = 0.35

    var toggleActivationMethod: ToggleActivationMethod = .shortcut
    private(set) var pendingHoldStartedAt: Date?
    private var lastTapReleasedAt: Date?

    var pendingHoldDeadline: Date? {
        pendingHoldStartedAt?.addingTimeInterval(Self.holdThreshold)
    }
    /// How the current session was started, or nil when idle.
    private(set) var activeMode: RecordingTriggerMode?

    var isActive: Bool { activeMode != nil }

    mutating func reset() {
        activeMode = nil
        pendingHoldStartedAt = nil
        lastTapReleasedAt = nil
    }

    /// The session ended somewhere else (menu item, overlay button, error).
    mutating func sessionDidStopExternally() {
        reset()
    }

    /// In double-tap mode the first press gets a short chance to become a tap.
    /// Only a sustained hold starts the microphone; isolated taps do nothing.
    mutating func advanceTime(to time: Date) -> [DictationShortcutAction] {
        guard activeMode == nil, let deadline = pendingHoldDeadline, time >= deadline else { return [] }
        pendingHoldStartedAt = nil
        lastTapReleasedAt = nil
        activeMode = .hold
        return [.start(.hold)]
    }

    mutating func handle(_ event: ShortcutEvent, at time: Date = Date()) -> [DictationShortcutAction] {
        if toggleActivationMethod == .doubleTapHold {
            return handleDoubleTap(event, at: time)
        }
        switch event {
        case .holdActivated:
            guard activeMode == nil else { return [] }
            activeMode = .hold
            return [.start(.hold)]

        case .holdDeactivated:
            guard activeMode == .hold else { return [] }
            activeMode = nil
            return [.stop]

        case .toggleActivated:
            switch activeMode {
            case .none:
                activeMode = .toggle
                return [.start(.toggle)]
            case .hold:
                activeMode = .toggle
                return [.switchedToToggle]
            case .toggle:
                activeMode = nil
                return [.stop]
            }

        case .toggleDeactivated:
            return []

        case .copyAgainTriggered:
            return []
        }
    }

    private mutating func handleDoubleTap(_ event: ShortcutEvent, at time: Date) -> [DictationShortcutAction] {
        switch event {
        case .holdActivated:
            if activeMode == .toggle {
                reset()
                return [.stop]
            }
            guard activeMode == nil, pendingHoldStartedAt == nil else { return [] }
            if let released = lastTapReleasedAt,
               time >= released, time.timeIntervalSince(released) <= Self.doubleTapInterval {
                lastTapReleasedAt = nil
                activeMode = .toggle
                return [.start(.toggle)]
            }
            lastTapReleasedAt = nil
            pendingHoldStartedAt = time
            return []

        case .holdDeactivated:
            if activeMode == .hold {
                reset()
                return [.stop]
            }
            if let pressed = pendingHoldStartedAt {
                let duration = time.timeIntervalSince(pressed)
                lastTapReleasedAt = duration >= 0 && duration < Self.holdThreshold ? time : nil
                pendingHoldStartedAt = nil
            }
            return []

        case .toggleActivated, .toggleDeactivated, .copyAgainTriggered:
            return []
        }
    }
}
