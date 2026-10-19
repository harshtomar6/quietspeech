import AppKit
import os

// Derived from FreeFlow (https://github.com/zachlatta/freeflow),
// Sources/GlobalShortcutBackend.swift, Copyright (c) Zach Latta, MIT licensed.
//
// One active `CGEventTap` over flagsChanged + keyDown + keyUp, feeding the
// matcher. The tap answer is synchronous by necessity: the only moment we can
// swallow a keystroke so it never reaches the focused app is inside the
// callback, so matching runs there (under a lock, since configuration changes
// arrive from the main thread) and matched events return nil.
//
// The tap is created `.defaultTap`, which is what lets us consume. macOS picks
// the TCC service from that flag, not the tap location:
//
//   .listenOnly -> kTCCServiceListenEvent   (Input Monitoring)
//   .defaultTap -> kTCCServicePostEvent     (Accessibility)
//
// Accessibility is needed anyway to type the transcript into other apps, so
// routing activation through it keeps this to one permission. `tapCreate` also
// returns nil for `.defaultTap` when the grant is missing, making this a
// trustworthy permission probe.
final class ShortcutBackend: @unchecked Sendable {

    /// Delivered on the main queue, in the order the matcher produced them.
    var onEvent: ((ShortcutEvent) -> Void)?
    /// Reported when the tap cannot be created (missing Accessibility).
    var onTapUnavailable: ((String) -> Void)?
    /// Reports whether the event tap is actually live.
    var onTapStatusChanged: ((Bool) -> Void)?

    private(set) var tapActive = false

    private var matcher = ShortcutMatcher()
    private var captureMode = false
    private let lock = NSLock()
    private let log = Logger(subsystem: "dev.harsh.whisprproto", category: "tap")

    private var tapThread: Thread?
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?

    // MARK: - Lifecycle

    /// Creates the event tap if it isn't live yet. Safe to call repeatedly —
    /// this is how we recover after the user grants Accessibility without
    /// relaunching.
    @discardableResult
    func ensureTap() -> Bool {
        if tapActive { return true }
        if tapThread != nil { stopTap() }

        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: ShortcutBackend.tapCallback,
            userInfo: refcon
        ) else {
            tapActive = false
            onTapUnavailable?("Accessibility permission is required for the activation shortcut. Grant it in System Settings > Privacy & Security > Accessibility, then click Relaunch.")
            onTapStatusChanged?(false)
            return false
        }

        tap = created
        let thread = Thread { [weak self] in
            guard let self else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
            self.lock.lock()
            self.runLoop = CFRunLoopGetCurrent()
            self.lock.unlock()
            CFRunLoopRun()
        }
        thread.name = "app.whisprproto.shortcut-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
        tapActive = true
        onTapStatusChanged?(true)
        return true
    }

    func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        lock.lock()
        let loop = runLoop
        runLoop = nil
        tap = nil
        lock.unlock()
        if let loop { CFRunLoopStop(loop) }
        tapThread = nil
        tapActive = false
    }

    /// Replaces the active bindings. Never throws; reports problems.
    func apply(configuration: ShortcutConfiguration) {
        lock.lock()
        matcher.update(configuration: configuration)
        lock.unlock()
        if !configuration.isDisabled { ensureTap() }
    }

    /// Suspends matching while the settings window is recording a new binding,
    /// so the keystroke being recorded can't fire the binding it replaces.
    func setCaptureMode(_ capturing: Bool) {
        lock.lock()
        let wasCapturing = captureMode
        captureMode = capturing
        if capturing && !wasCapturing { matcher.reset() }
        lock.unlock()
    }

    // MARK: - Tap

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let backend = Unmanaged<ShortcutBackend>.fromOpaque(refcon).takeUnretainedValue()
        return backend.process(type: type, event: event)
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables a tap if it takes too long or the user revokes
        // permission; re-enable so we keep receiving events.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Key repeat carries no new information and must not be swallowed.
        if (type == .keyDown || type == .keyUp),
           event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
            return Unmanaged.passUnretained(event)
        }

        let decision: ShortcutMatcher.ConsumeDecision
        lock.lock()
        if captureMode {
            lock.unlock()
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .flagsChanged:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == 0 {
                let pressed = ShortcutBinding.modifierKeyCodes.filter { code in
                    guard let flag = ModifierKeyEventState.mappedFlag(for: code) else { return false }
                    return event.flags.contains(flag)
                }
                decision = matcher.handle(.modifierSnapshot(Set(pressed)))
            } else {
                let flag = ModifierKeyEventState.mappedFlag(for: keyCode) ?? .maskSecondaryFn
                let isDown = event.flags.contains(flag)
                decision = matcher.handle(.modifierChanged(keyCode: keyCode, isDown: isDown))
            }

        case .keyDown, .keyUp:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            decision = matcher.handle(.keyChanged(keyCode: keyCode, isDown: type == .keyDown))

        default:
            decision = .passthrough
        }
        let events = matcher.drainEvents()
        lock.unlock()

        if type == .flagsChanged || type == .keyDown || type == .keyUp {
            // Debug level on purpose: at notice this would log every keystroke
            // on the machine.
            log.debug("""
            raw \(String(describing: type), privacy: .public) \
            code=\(event.getIntegerValueField(.keyboardEventKeycode), privacy: .public) \
            flags=\(event.flags.rawValue, privacy: .public) \
            decision=\(String(describing: decision), privacy: .public) \
            events=\(events.map { String(describing: $0) }.joined(separator: ","), privacy: .public)
            """)
        }

        for event in events {
            DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
        }

        return decision == .consume ? nil : Unmanaged.passUnretained(event)
    }
}
