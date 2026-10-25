import Foundation

// Derived from FreeFlow (https://github.com/zachlatta/freeflow),
// Sources/ShortcutCore/ShortcutMatcher.swift, Copyright (c) Zach Latta, MIT
// licensed.
//
// Turns raw key/modifier events into `ShortcutEvent`s, deciding at the same
// time whether the keystroke should be swallowed so the bound keys never reach
// the focused app. The latch (start holding Fn, then add Cmd to keep going)
// surfaces as `toggleActivated` while the hold is still down; the session
// controller turns that into `switchedToToggle` so recording is never stopped
// and restarted.

/// Which keys are physically down.
struct ShortcutInputState: Equatable {
    var pressedKeyCodes: Set<UInt16> = []
    var pressedModifierKeyCodes: Set<UInt16> = []

    var isEmpty: Bool {
        pressedKeyCodes.isEmpty && pressedModifierKeyCodes.isEmpty
    }
}

struct ShortcutMatcher {
    enum InputEvent: Equatable {
        /// A single modifier key went down or up (flagsChanged).
        case modifierChanged(keyCode: UInt16, isDown: Bool)
        /// A full resync of which modifiers are down, after a tap restart.
        case modifierSnapshot(Set<UInt16>)
        /// A non-modifier key went down or up.
        case keyChanged(keyCode: UInt16, isDown: Bool)
        /// The backend lost its stream; forget everything.
        case backendReset
    }

    enum ConsumeDecision: Equatable {
        case consume
        case passthrough
    }

    private(set) var configuration: ShortcutConfiguration

    private var state = ShortcutInputState()
    private var holdIsActive = false
    private var toggleIsActive = false
    private var copyAgainIsActive = false
    private var pendingEvents: [ShortcutEvent] = []
    /// Keys we swallowed on the way down, so their release is swallowed too.
    /// A half-consumed keystroke (down held back, up delivered) would let the
    /// app see an up it never asked for.
    private var consumedModifierKeyCodes: Set<UInt16> = []
    private var consumedKeyCodes: Set<UInt16> = []

    init(configuration: ShortcutConfiguration = .defaultConfiguration) {
        self.configuration = configuration
    }

    var isAnyBindingActive: Bool {
        holdIsActive || toggleIsActive
    }

    mutating func update(configuration: ShortcutConfiguration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        reset()
    }

    mutating func reset() {
        state = ShortcutInputState()
        holdIsActive = false
        toggleIsActive = false
        copyAgainIsActive = false
        pendingEvents.removeAll()
        consumedModifierKeyCodes.removeAll()
        consumedKeyCodes.removeAll()
    }

    mutating func drainEvents() -> [ShortcutEvent] {
        defer { pendingEvents.removeAll() }
        return pendingEvents
    }

    mutating func handle(_ event: InputEvent) -> ConsumeDecision {
        switch event {
        case let .modifierChanged(keyCode, isDown):
            guard ModifierKeyEventState.isModifierKeyCode(keyCode) else { return .passthrough }
            if isDown {
                state.pressedModifierKeyCodes.insert(keyCode)
                refreshEdges()
                let decision = modifierDownDecision(for: keyCode)
                if decision == .consume { consumedModifierKeyCodes.insert(keyCode) }
                return decision
            } else {
                let decision: ConsumeDecision = consumedModifierKeyCodes.contains(keyCode) ? .consume : .passthrough
                state.pressedModifierKeyCodes.remove(keyCode)
                refreshEdges()
                consumedModifierKeyCodes.remove(keyCode)
                return decision
            }

        case let .modifierSnapshot(pressed):
            state.pressedModifierKeyCodes = pressed.intersection(ShortcutBinding.modifierKeyCodes)
            refreshEdges()
            return .passthrough

        case let .keyChanged(keyCode, isDown):
            guard !ModifierKeyEventState.isModifierKeyCode(keyCode) else {
                return .passthrough
            }
            if isDown {
                state.pressedKeyCodes.insert(keyCode)
                refreshEdges()
                let decision = keyConsumeDecision(for: keyCode)
                if decision == .consume { consumedKeyCodes.insert(keyCode) }
                return decision
            } else {
                let decision: ConsumeDecision = consumedKeyCodes.contains(keyCode) ? .consume : .passthrough
                state.pressedKeyCodes.remove(keyCode)
                refreshEdges()
                consumedKeyCodes.remove(keyCode)
                return decision
            }

        case .backendReset:
            reset()
            return .passthrough
        }
    }

    // MARK: - Edge detection

    private mutating func refreshEdges() {
        let nowHold = isActive(configuration.hold)
        let nowToggle = isActive(configuration.toggle)
        let nowCopyAgain = isActive(configuration.copyAgain)

        if nowHold != holdIsActive {
            pendingEvents.append(nowHold ? .holdActivated : .holdDeactivated)
            holdIsActive = nowHold
        }
        if nowToggle != toggleIsActive {
            pendingEvents.append(nowToggle ? .toggleActivated : .toggleDeactivated)
            toggleIsActive = nowToggle
        }
        if nowCopyAgain != copyAgainIsActive {
            copyAgainIsActive = nowCopyAgain
            if nowCopyAgain { pendingEvents.append(.copyAgainTriggered) }
        }
    }

    private func isActive(_ binding: ShortcutBinding) -> Bool {
        guard !binding.isDisabled else { return false }

        let pressedModifiers = state.pressedModifierKeyCodes
        guard ShortcutBinding.modifiers(for: pressedModifiers).isSuperset(of: binding.modifiers) else {
            return false
        }

        if let exactModifierKeyCodes = binding.exactModifierKeyCodes,
           !ShortcutBinding.exactModifierKeyCodesMatch(
               pressedModifiers,
               exactModifierKeyCodes: exactModifierKeyCodes,
               permittedAdditionalExactMatchModifiers: configuration.permittedAdditionalExactMatchModifiers
           ) {
            return false
        }

        switch binding.kind {
        case .disabled:
            return false
        case .key:
            return state.pressedKeyCodes.contains(binding.keyCode)
        case .modifierKey:
            return pressedModifiers.contains(binding.keyCode)
        }
    }

    // MARK: - Consume decisions

    private func modifierDownDecision(for keyCode: UInt16) -> ConsumeDecision {
        // While a binding is doing its job, its modifiers belong to us.
        if holdIsActive || toggleIsActive || copyAgainIsActive { return .consume }

        // A modifier-key binding swallows its own key from the first press, so
        // Fn never reaches the system and cannot open the emoji picker on the
        // way to the shortcut. A modifier that only decorates a *key* binding
        // (Cmd in Cmd+Space) is deliberately left alone — swallowing Cmd would
        // break every other shortcut on the machine.
        for binding in [configuration.hold, configuration.toggle, configuration.copyAgain]
        where binding.kind == .modifierKey && binding.keyCode == keyCode {
            return .consume
        }
        return .passthrough
    }

    private func keyConsumeDecision(for keyCode: UInt16) -> ConsumeDecision {
        for binding in [configuration.hold, configuration.toggle, configuration.copyAgain] {
            guard binding.kind == .key, binding.keyCode == keyCode else { continue }
            if isActive(binding) { return .consume }
        }
        return .passthrough
    }
}

private extension ShortcutBinding {
    /// True when this binding's own keys include `keyCode` — either the primary
    /// key or any modifier that satisfies it.
    func references(keyCode: UInt16) -> Bool {
        guard !isDisabled else { return false }
        if kind == .modifierKey, self.keyCode == keyCode { return true }
        if kind == .key, self.keyCode == keyCode { return true }
        if let exactModifierKeyCodes, exactModifierKeyCodes.contains(keyCode) { return true }
        return ShortcutBinding.matchingModifierKeyCodes(for: modifiers).contains(keyCode)
    }

    /// True when any of the modifiers this binding currently needs are down.
    func referencesPressedModifiers(_ pressed: Set<UInt16>) -> Bool {
        guard !isDisabled else { return false }
        if let exactModifierKeyCodes, !exactModifierKeyCodes.isDisjoint(with: pressed) {
            return true
        }
        return !ShortcutBinding.matchingModifierKeyCodes(for: modifiers).isDisjoint(with: pressed)
    }
}
