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
    /// How the current session was started, or nil when idle.
    private(set) var activeMode: RecordingTriggerMode?

    var isActive: Bool { activeMode != nil }

    mutating func reset() {
        activeMode = nil
    }

    /// The session ended somewhere else (menu item, overlay button, error).
    mutating func sessionDidStopExternally() {
        activeMode = nil
    }

    mutating func handle(_ event: ShortcutEvent) -> [DictationShortcutAction] {
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
}
