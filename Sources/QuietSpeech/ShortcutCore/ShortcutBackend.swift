import AppKit
import os
import Synchronization

// Derived from FreeFlow (https://github.com/zachlatta/freeflow),
// Sources/GlobalShortcutBackend.swift, Copyright (c) Zach Latta, MIT licensed.
//
// One active `CGEventTap` over flagsChanged + keyDown + keyUp, feeding the
// matcher. The tap answer is synchronous by necessity: the only moment we can
// swallow a keystroke so it never reaches the focused app is inside the
// callback, so matching runs there (under a nonblocking lock, since configuration changes
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
    var onEvent: ((ShortcutEvent, Date) -> Void)?
    var onTapUnavailable: ((String) -> Void)?
    var onTapStatusChanged: ((Bool) -> Void)?
    /// Delivered on the main queue; the current shortcut session must end.
    var onInputInterrupted: ((String) -> Void)?

    var tapActive: Bool { active.load(ordering: .acquiring) }
    private let active = Atomic(false)
    private let passThrough = Atomic(false)
    private let resetRequested = Atomic(false)
    private let interruptionQueued = Atomic(false)
    private let deliveryGeneration = Atomic<UInt64>(0)
    private let tapGeneration = Atomic<UInt64>(0)
    private var matcher = ShortcutMatcher()
    private var captureMode = false
    private let lock: NSLock
    private let permissionCheck: () -> Bool
    // Accessed only by main-actor lifecycle methods, never by the callback.
    private var session: TapSession?
    private var permissionMonitor: DispatchSourceTimer?
    private let log = Logger(subsystem: "dev.harsh.quietspeech", category: "tap")

    init(lock: NSLock = NSLock(), permissionCheck: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.lock = lock
        self.permissionCheck = permissionCheck
    }

    deinit {
        permissionMonitor?.cancel()
        session?.stop()
    }

    @MainActor
    @discardableResult
    func ensureTap() -> Bool {
        guard permissionCheck() else {
            stopTap()
            onTapUnavailable?("Accessibility permission is required for the activation shortcut. Grant it in System Settings > Privacy & Security > Accessibility, then click Recheck or Relaunch.")
            return false
        }
        if tapActive {
            onTapStatusChanged?(true)
            return true
        }
        if session != nil { stopTap() }

        let token = tapGeneration.wrappingAdd(1, ordering: .acquiringAndReleasing).newValue
        let context = CallbackContext(owner: self, token: token)
        let mask = CGEventMask((1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else {
            passThrough.store(true, ordering: .releasing)
            onTapUnavailable?("The activation shortcut could not start. Check Accessibility permission, then click Recheck.")
            onTapStatusChanged?(false)
            return false
        }
        // New taps are enabled by default. Do not leave one enabled while
        // its dedicated thread and run-loop source are still starting up.
        CGEvent.tapEnable(tap: port, enable: false)
        let session = TapSession(port: port, context: context)
        self.session = session
        passThrough.store(false, ordering: .releasing)
        resetRequested.store(true, ordering: .releasing)
        interruptionQueued.store(false, ordering: .releasing)
        active.store(true, ordering: .releasing)
        let thread = Thread { session.run() }
        thread.name = "app.quietspeech.shortcut-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        log.notice("shortcut listener created generation=\(token, privacy: .public)")
        startPermissionMonitor()
        onTapStatusChanged?(true)
        return true
    }

    @MainActor
    func stopTap() {
        passThrough.store(true, ordering: .releasing)
        active.store(false, ordering: .releasing)
        _ = tapGeneration.wrappingAdd(1, ordering: .acquiringAndReleasing)
        _ = deliveryGeneration.wrappingAdd(1, ordering: .acquiringAndReleasing)
        permissionMonitor?.cancel()
        permissionMonitor = nil
        session?.stop()
        session = nil
        lock.lock()
        matcher.reset()
        resetRequested.store(false, ordering: .releasing)
        lock.unlock()
        onTapStatusChanged?(false)
    }

    @MainActor
    func apply(configuration: ShortcutConfiguration) {
        lock.lock()
        if matcher.configuration != configuration {
            _ = deliveryGeneration.wrappingAdd(1, ordering: .acquiringAndReleasing)
            matcher.update(configuration: configuration)
        }
        lock.unlock()
        if configuration.isDisabled { stopTap() } else { ensureTap() }
    }

    @MainActor
    func setCaptureMode(_ capturing: Bool) {
        lock.lock()
        if captureMode != capturing {
            captureMode = capturing
            matcher.reset()
            _ = deliveryGeneration.wrappingAdd(1, ordering: .acquiringAndReleasing)
        }
        lock.unlock()
    }

    @MainActor
    private func startPermissionMonitor() {
        permissionMonitor?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.tapActive, !self.permissionCheck() else { return }
                self.stopTap()
                let message = "Accessibility permission was removed. Shortcuts are paused; grant access and click Recheck to restart them."
                self.log.error("shortcut listener stopped: Accessibility permission removed")
                self.onInputInterrupted?(message)
            }
        }
        permissionMonitor = timer
        timer.resume()
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<CallbackContext>.fromOpaque(refcon).takeUnretainedValue()
        guard let backend = context.owner else { return Unmanaged.passUnretained(event) }
        return backend.process(type: type, event: event, tapToken: context.token)
    }

    // Internal so tests can replay unposted events without a global tap.
    func process(type: CGEventType, event: CGEvent, tapToken: UInt64? = nil) -> Unmanaged<CGEvent>? {
        let token = tapGeneration.load(ordering: .acquiring)
        guard tapToken == nil || tapToken == token else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Never repeatedly re-enable an unhealthy or user-disabled tap.
            // Immediately fail open, invalidate queued activations, and let
            // the user explicitly retry through Recheck or shortcut settings.
            passThrough.store(true, ordering: .releasing)
            resetRequested.store(true, ordering: .releasing)
            if !interruptionQueued.exchange(true, ordering: .acquiringAndReleasing) {
                let reason = type == .tapDisabledByTimeout ? "timeout" : "user disable"
                _ = deliveryGeneration.wrappingAdd(1, ordering: .acquiringAndReleasing)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.tapGeneration.load(ordering: .acquiring) == token else { return }
                    // Our intentional startup disable can leave a queued
                    // notification after the worker has already enabled the
                    // port. Inspect it outside the input callback; this does
                    // not re-enable a disabled port or ignore permission loss.
                    if let session = self.session,
                       CGEvent.tapIsEnabled(tap: session.port), self.permissionCheck() {
                        self.onInputInterrupted?("The shortcut input stream restarted. Release the keys and try again.")
                        self.passThrough.store(false, ordering: .releasing)
                        self.active.store(true, ordering: .releasing)
                        self.interruptionQueued.store(false, ordering: .releasing)
                        self.onTapStatusChanged?(true)
                        self.log.notice("discarded a stale disable notification for an enabled listener")
                        return
                    }
                    self.stopTap()
                    self.log.error("shortcut listener paused: \(reason, privacy: .public)")
                    self.onInputInterrupted?("The shortcut listener was interrupted and has been paused. Click Recheck in Permissions to restart it.")
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .flagsChanged || type == .keyDown || type == .keyUp,
              !passThrough.load(ordering: .acquiring),
              event.getIntegerValueField(.eventSourceUserData) != KeyboardEventSource.marker else {
            return Unmanaged.passUnretained(event)
        }
        if type != .flagsChanged, event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
            return Unmanaged.passUnretained(event)
        }

        guard lock.try() else {
            guard !passThrough.load(ordering: .acquiring),
                  tapGeneration.load(ordering: .acquiring) == token else {
                return Unmanaged.passUnretained(event)
            }
            if !resetRequested.exchange(true, ordering: .acquiringAndReleasing) {
                let resetGeneration = deliveryGeneration.wrappingAdd(1, ordering: .acquiringAndReleasing).newValue
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.deliveryGeneration.load(ordering: .acquiring) == resetGeneration else { return }
                    self.onInputInterrupted?("Shortcut input was interrupted. Release the shortcut keys and try again.")
                }
            }
            return Unmanaged.passUnretained(event)
        }
        let generation = deliveryGeneration.load(ordering: .acquiring)
        if resetRequested.exchange(false, ordering: .acquiringAndReleasing) { matcher.reset() }
        if captureMode || passThrough.load(ordering: .acquiring)
            || tapGeneration.load(ordering: .acquiring) != token {
            lock.unlock()
            return Unmanaged.passUnretained(event)
        }
        let decision: ShortcutMatcher.ConsumeDecision
        if type == .flagsChanged {
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if code == 0 {
                let pressed = ShortcutBinding.modifierKeyCodes.filter { code in
                    guard let flag = ModifierKeyEventState.mappedFlag(for: code) else { return false }
                    return event.flags.contains(flag)
                }
                decision = matcher.handle(.modifierSnapshot(Set(pressed)))
            } else {
                let flag = ModifierKeyEventState.mappedFlag(for: code) ?? .maskSecondaryFn
                decision = matcher.handle(.modifierChanged(keyCode: code, isDown: event.flags.contains(flag)))
            }
        } else {
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            decision = matcher.handle(.keyChanged(keyCode: code, isDown: type == .keyDown))
        }
        let events = matcher.drainEvents()
        lock.unlock()
        if !events.isEmpty {
            let receivedAt = Date()
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.passThrough.load(ordering: .acquiring),
                      self.tapGeneration.load(ordering: .acquiring) == token,
                      self.deliveryGeneration.load(ordering: .acquiring) == generation else { return }
                for event in events { self.onEvent?(event, receivedAt) }
            }
        }
        let stillCurrent = !passThrough.load(ordering: .acquiring)
            && deliveryGeneration.load(ordering: .acquiring) == generation
            && tapGeneration.load(ordering: .acquiring) == token
        return decision == .consume && stillCurrent ? nil : Unmanaged.passUnretained(event)
    }

    private final class CallbackContext {
        weak var owner: ShortcutBackend?
        let token: UInt64
        init(owner: ShortcutBackend, token: UInt64) { self.owner = owner; self.token = token }
    }

    private final class TapSession: @unchecked Sendable {
        let port: CFMachPort
        let context: CallbackContext
        private let lifecycle = ShortcutTapLifecycle()
        private var runLoop: CFRunLoop?
        init(port: CFMachPort, context: CallbackContext) { self.port = port; self.context = context }

        func run() {
            let loop = CFRunLoopGetCurrent()!
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
                DispatchQueue.main.async { [context] in
                    guard let owner = context.owner,
                          owner.tapGeneration.load(ordering: .acquiring) == context.token else { return }
                    owner.stopTap()
                    owner.onTapUnavailable?("The shortcut listener could not start. Click Recheck in Permissions to retry.")
                }
                return
            }
            guard lifecycle.start({
                runLoop = loop
                CFRunLoopAddSource(loop, source, .commonModes)
                CGEvent.tapEnable(tap: port, enable: true)
            }) else { return }
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }

        func stop() {
            var loop: CFRunLoop?
            lifecycle.stop {
                CGEvent.tapEnable(tap: port, enable: false)
                loop = runLoop
                runLoop = nil
            }
            if let loop {
                // Queue the stop too, so cancellation cannot be lost between
                // publishing the loop and entering CFRunLoopRun().
                CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) {
                    CFRunLoopStop(CFRunLoopGetCurrent())
                }
                CFRunLoopWakeUp(loop)
            }
        }
    }
}

/// Serializes startup/cancellation independently of the input callback lock.
final class ShortcutTapLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    @discardableResult
    func start(_ enable: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return false }
        enable()
        return true
    }

    func stop(_ disable: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        stopped = true
        disable()
    }
}
