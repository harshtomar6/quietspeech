import Foundation

// Derived from FreeFlow (https://github.com/zachlatta/freeflow),
// Sources/ShortcutCore/ShortcutModels.swift, Copyright (c) Zach Latta,
// MIT licensed.
//
// Local changes: `ShortcutConfiguration` is `Codable` and gains
// `defaultConfiguration` so the two bindings can be persisted in UserDefaults.

struct ShortcutModifiers: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let control = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)
    static let function = ShortcutModifiers(rawValue: 1 << 4)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Translates `NSEvent.ModifierFlags.rawValue` (the encoding the old
    /// single-shortcut preference used) into logical modifiers.
    init(nsEventFlags: UInt) {
        var value: ShortcutModifiers = []
        if nsEventFlags & (1 << 20) != 0 { value.insert(.command) }
        if nsEventFlags & (1 << 18) != 0 { value.insert(.control) }
        if nsEventFlags & (1 << 19) != 0 { value.insert(.option) }
        if nsEventFlags & (1 << 17) != 0 { value.insert(.shift) }
        if nsEventFlags & (1 << 23) != 0 { value.insert(.function) }
        self = value
    }

    var orderedDisplayNames: [String] {
        var names: [String] = []
        if contains(.command) { names.append("Cmd ⌘") }
        if contains(.control) { names.append("Ctrl ⌃") }
        if contains(.option) { names.append("Option ⌥") }
        if contains(.shift) { names.append("Shift ⇧") }
        if contains(.function) { names.append("Fn 🌐") }
        return names
    }
}

enum ShortcutBindingKind: String, Codable {
    case disabled
    case key
    case modifierKey
}

enum RecordingTriggerMode: String, Codable {
    case hold
    case toggle

    var badgeTitle: String {
        switch self {
        case .hold: return "Hold"
        case .toggle: return "Tap"
        }
    }
}

enum ShortcutRole: String, CaseIterable {
    case hold
    case toggle
    case copyAgain

    var title: String {
        switch self {
        case .hold: return "Hold to Talk"
        case .toggle: return "Tap to Toggle"
        case .copyAgain: return "Paste Again"
        }
    }

    var detail: String {
        switch self {
        case .hold: return "Speak while the keys are down."
        case .toggle: return "Press once to start, again to stop."
        case .copyAgain: return "Re-paste the last dictation."
        }
    }
}

enum ShortcutEvent: Equatable {
    case holdActivated
    case holdDeactivated
    case toggleActivated
    case toggleDeactivated
    case copyAgainTriggered
}

struct ShortcutConfiguration: Equatable, Codable {
    let hold: ShortcutBinding
    let toggle: ShortcutBinding
    let copyAgain: ShortcutBinding
    let permittedAdditionalExactMatchModifiers: ShortcutModifiers

    init(
        hold: ShortcutBinding,
        toggle: ShortcutBinding,
        copyAgain: ShortcutBinding = .disabled,
        permittedAdditionalExactMatchModifiers: ShortcutModifiers = []
    ) {
        self.hold = hold
        self.toggle = toggle
        self.copyAgain = copyAgain
        self.permittedAdditionalExactMatchModifiers = permittedAdditionalExactMatchModifiers
    }

    static let disabled = ShortcutConfiguration(hold: .disabled, toggle: .disabled, copyAgain: .disabled)

    /// Fn alone holds, Fn + Cmd taps — including the latch: start holding Fn,
    /// then add Cmd to switch into tap mode without stopping the recording.
    static let defaultConfiguration = ShortcutConfiguration(
        hold: ShortcutPreset.fnKey.binding,
        toggle: ShortcutPreset.fnKey.binding.withAddedModifiers(.command)
    )

    var isDisabled: Bool {
        hold.isDisabled && toggle.isDisabled && copyAgain.isDisabled
    }

    func binding(for role: ShortcutRole) -> ShortcutBinding {
        switch role {
        case .hold: return hold
        case .toggle: return toggle
        case .copyAgain: return copyAgain
        }
    }

    func replacing(_ role: ShortcutRole, with binding: ShortcutBinding) -> ShortcutConfiguration {
        ShortcutConfiguration(
            hold: role == .hold ? binding : hold,
            toggle: role == .toggle ? binding : toggle,
            copyAgain: role == .copyAgain ? binding : copyAgain,
            permittedAdditionalExactMatchModifiers: permittedAdditionalExactMatchModifiers
        )
    }

    /// Pairs of roles whose bindings would fire on the same keystroke.
    var conflictingRoles: [(ShortcutRole, ShortcutRole)] {
        var found: [(ShortcutRole, ShortcutRole)] = []
        let roles = ShortcutRole.allCases
        for (index, role) in roles.enumerated() {
            for other in roles[(index + 1)...] {
                if binding(for: role).conflicts(with: binding(for: other)) {
                    found.append((role, other))
                }
            }
        }
        return found
    }
}

extension ShortcutConfiguration {
    /// Human summary for the menu bar and the settings header.
    var summary: String {
        var parts: [String] = []
        if !hold.isDisabled { parts.append("Hold \(hold.displayName)") }
        if !toggle.isDisabled { parts.append("Tap \(toggle.displayName)") }
        if !copyAgain.isDisabled { parts.append("Again \(copyAgain.displayName)") }
        return parts.isEmpty ? "Disabled" : parts.joined(separator: " \u{00b7} ")
    }

    var holdModeEnabled: Bool { !hold.isDisabled }
    var toggleModeEnabled: Bool { !toggle.isDisabled }
}

/// Names for the physical keys a binding can use.
enum ShortcutKeyNames {
    static func name(forKeyCode keyCode: UInt16) -> String {
        if let modifier = ShortcutBinding.exactModifierDisplayLabel(for: keyCode) {
            return modifier
        }
        return table[keyCode] ?? "Key \(keyCode)"
    }

    private static let table: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 53: "Esc", 51: "Delete",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
        96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
        35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
        13: "W", 7: "X", 16: "Y", 6: "Z"
    ]
}

enum ShortcutPreset: String, CaseIterable, Identifiable, Codable {
    case fnKey = "fn"
    case rightOption = "rightOption"
    case f5 = "f5"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fnKey: return "Fn 🌐"
        case .rightOption: return "Right Option ⌥"
        case .f5: return "F5"
        }
    }

    var binding: ShortcutBinding {
        switch self {
        case .fnKey:
            return ShortcutBinding(
                keyCode: 63,
                keyDisplay: "Fn",
                modifiers: [],
                kind: .modifierKey,
                preset: self
            )
        case .rightOption:
            return ShortcutBinding(
                keyCode: 61,
                keyDisplay: "Right Option",
                modifiers: [],
                kind: .modifierKey,
                preset: self
            )
        case .f5:
            return ShortcutBinding(
                keyCode: 96,
                keyDisplay: "F5",
                modifiers: [],
                kind: .key,
                preset: self
            )
        }
    }
}

struct ShortcutBinding: Codable, Hashable, Identifiable, Equatable {
    let keyCode: UInt16
    let keyDisplay: String
    let modifiers: ShortcutModifiers
    let kind: ShortcutBindingKind
    let preset: ShortcutPreset?
    let exactModifierKeyCodes: Set<UInt16>?

    init(
        keyCode: UInt16,
        keyDisplay: String,
        modifiers: ShortcutModifiers,
        kind: ShortcutBindingKind,
        preset: ShortcutPreset?,
        exactModifierKeyCodes: Set<UInt16>? = nil
    ) {
        self.keyCode = keyCode
        self.keyDisplay = keyDisplay
        self.modifiers = modifiers
        self.kind = kind
        self.preset = preset
        self.exactModifierKeyCodes = exactModifierKeyCodes
    }

    var id: String {
        let exactModifierID = Self.orderedExactModifierKeyCodes(
            exactModifierKeyCodes ?? []
        ).map(String.init).joined(separator: ",")
        return "\(kind.rawValue):\(keyCode):\(modifiers.rawValue):\(preset?.rawValue ?? "custom"):\(exactModifierID)"
    }

    var displayName: String {
        if isDisabled { return "Disabled" }
        let parts = modifierDisplayNames + [primaryDisplayName]
        return parts.joined(separator: " + ")
    }

    var selectionTitle: String {
        preset?.title ?? displayName
    }

    var isCustom: Bool {
        preset == nil && !isDisabled
    }

    var isDisabled: Bool {
        kind == .disabled
    }

    var specificityScore: Int {
        modifierDisplayNames.count
    }

    var usesFnKey: Bool {
        guard !isDisabled else { return false }
        return keyCode == 63 || modifiers.contains(.function)
    }

    var requiresExactModifierMatch: Bool {
        kind == .modifierKey || exactModifierKeyCodes != nil
    }

    func withAddedModifiers(_ extraModifiers: ShortcutModifiers) -> ShortcutBinding {
        guard !isDisabled else { return self }
        let updatedModifiers = modifiers.union(extraModifiers)
        let updatedExactModifierKeyCodes: Set<UInt16>?
        if let exactModifierKeyCodes, !exactModifierKeyCodes.isEmpty {
            updatedExactModifierKeyCodes = Self.normalizedExactModifierKeyCodes(
                exactModifierKeyCodes.union(Self.exactModifierKeyCodesPreservingSides(for: extraModifiers))
            )
        } else {
            updatedExactModifierKeyCodes = exactModifierKeyCodes
        }

        return ShortcutBinding(
            keyCode: keyCode,
            keyDisplay: keyDisplay,
            modifiers: updatedModifiers,
            kind: kind,
            preset: preset,
            exactModifierKeyCodes: updatedExactModifierKeyCodes
        )
    }

    func conflicts(with other: ShortcutBinding) -> Bool {
        guard !isDisabled, !other.isDisabled else { return false }
        guard primaryInputOverlaps(with: other) else { return false }

        let orderedModifierKeyCodes = Array(Self.modifierKeyCodes).sorted()
        let combinations = 1 << orderedModifierKeyCodes.count

        for mask in 0..<combinations {
            var pressedModifierKeyCodes: Set<UInt16> = []
            for (index, keyCode) in orderedModifierKeyCodes.enumerated() where (mask & (1 << index)) != 0 {
                pressedModifierKeyCodes.insert(keyCode)
            }

            let selfActive = isActive(for: pressedModifierKeyCodes)
            let otherActive = other.isActive(for: pressedModifierKeyCodes)
            if selfActive && otherActive && specificityScore == other.specificityScore {
                return true
            }
        }

        return false
    }

    var modifierDisplayNames: [String] {
        Self.modifierDisplayNames(
            for: modifiers,
            exactModifierKeyCodes: displayedExactModifierKeyCodes
        )
    }

    private var primaryDisplayName: String {
        guard kind == .modifierKey,
              let exactDisplayName = Self.exactModifierDisplayLabel(for: keyCode) else {
            return keyDisplay
        }
        return exactDisplayName
    }

    private var displayedExactModifierKeyCodes: Set<UInt16>? {
        guard let exactModifierKeyCodes else { return nil }
        let filteredModifierKeyCodes: Set<UInt16>
        if kind == .modifierKey {
            filteredModifierKeyCodes = exactModifierKeyCodes.subtracting([keyCode])
        } else {
            filteredModifierKeyCodes = exactModifierKeyCodes
        }
        return Self.normalizedExactModifierKeyCodes(filteredModifierKeyCodes)
    }

    private func primaryInputOverlaps(with other: ShortcutBinding) -> Bool {
        guard kind == other.kind else { return false }

        switch kind {
        case .disabled:
            return false
        case .key:
            return keyCode == other.keyCode
        case .modifierKey:
            return keyCode == other.keyCode
        }
    }

    private func isActive(for pressedModifierKeyCodes: Set<UInt16>) -> Bool {
        let currentModifiers = Self.modifiers(for: pressedModifierKeyCodes)
        guard currentModifiers.isSuperset(of: modifiers) else {
            return false
        }

        if let exactModifierKeyCodes = exactModifierKeyCodes,
           !Self.exactModifierKeyCodesMatch(
            pressedModifierKeyCodes,
            exactModifierKeyCodes: exactModifierKeyCodes
           ) {
            return false
        }

        switch kind {
        case .disabled:
            return false
        case .key:
            return true
        case .modifierKey:
            return pressedModifierKeyCodes.contains(keyCode)
        }
    }

    static let disabled = ShortcutBinding(
        keyCode: 0,
        keyDisplay: "Disabled",
        modifiers: [],
        kind: .disabled,
        preset: nil
    )
    static let defaultHold = ShortcutPreset.fnKey.binding
    static let defaultToggle = ShortcutPreset.fnKey.binding.withAddedModifiers(.command)

    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    static func logicalModifier(forKeyCode keyCode: UInt16) -> ShortcutModifiers? {
        switch keyCode {
        case 54, 55:
            return .command
        case 59, 62:
            return .control
        case 58, 61:
            return .option
        case 56, 60:
            return .shift
        case 63:
            return .function
        default:
            return nil
        }
    }

    static func modifiers(for pressedModifierKeyCodes: Set<UInt16>) -> ShortcutModifiers {
        var modifiers: ShortcutModifiers = []
        for keyCode in pressedModifierKeyCodes {
            if let modifier = logicalModifier(forKeyCode: keyCode) {
                modifiers.insert(modifier)
            }
        }
        return modifiers
    }

    static func canonicalModifierKeyCode(for keyCode: UInt16) -> UInt16 {
        switch keyCode {
        case 54:
            return 55
        case 60:
            return 56
        case 61:
            return 58
        case 62:
            return 59
        default:
            return keyCode
        }
    }

    static func exactModifierKeyCodes(for modifiers: ShortcutModifiers) -> Set<UInt16> {
        var keyCodes: Set<UInt16> = []
        if modifiers.contains(.command) { keyCodes.insert(55) }
        if modifiers.contains(.control) { keyCodes.insert(59) }
        if modifiers.contains(.option) { keyCodes.insert(58) }
        if modifiers.contains(.shift) { keyCodes.insert(56) }
        if modifiers.contains(.function) { keyCodes.insert(63) }
        return keyCodes
    }

    static func exactModifierKeyCodesPreservingSides(for modifiers: ShortcutModifiers) -> Set<UInt16> {
        var keyCodes: Set<UInt16> = []
        if modifiers.contains(.command) { keyCodes.formUnion([54, 55]) }
        if modifiers.contains(.control) { keyCodes.formUnion([59, 62]) }
        if modifiers.contains(.option) { keyCodes.formUnion([58, 61]) }
        if modifiers.contains(.shift) { keyCodes.formUnion([56, 60]) }
        if modifiers.contains(.function) { keyCodes.insert(63) }
        return keyCodes
    }

    static func matchingModifierKeyCodes(for modifiers: ShortcutModifiers) -> Set<UInt16> {
        modifierKeyCodes.filter { keyCode in
            logicalModifier(forKeyCode: keyCode).map(modifiers.contains) == true
        }
    }

    static func logicalModifierDisplayLabel(for keyCode: UInt16) -> String {
        switch keyCode {
        case 55:
            return "Command"
        case 59:
            return "Control"
        case 58:
            return "Option"
        case 56:
            return "Shift"
        case 63:
            return "Fn"
        default:
            return "Modifier"
        }
    }

    /// Maps a modifier-key keyCode to the modifier mask it produces.
    /// Returns nil for non-modifier keyCodes.
    static func modifier(forKeyCode keyCode: UInt16) -> ShortcutModifiers? {
        for spec in modifierKeyCodeMatchSpecs {
            if spec.keyCodes.contains(keyCode) {
                return spec.logicalModifier
            }
        }
        return nil
    }

    static func exactModifierDisplayLabel(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 55:
            return "Cmd \u{2318}"
        case 54:
            return "Right Cmd \u{2318}"
        case 59:
            return "Ctrl \u{2303}"
        case 62:
            return "Right Ctrl \u{2303}"
        case 58:
            return "Option \u{2325}"
        case 61:
            return "Right Option \u{2325}"
        case 56:
            return "Shift \u{21E7}"
        case 60:
            return "Right Shift \u{21E7}"
        case 63:
            return "Fn"
        default:
            return nil
        }
    }

    static func normalizedExactModifierKeyCodes(_ exactModifierKeyCodes: Set<UInt16>?) -> Set<UInt16>? {
        guard let exactModifierKeyCodes else { return nil }
        let normalized = exactModifierKeyCodes.filter { modifierKeyCodes.contains($0) }
        return normalized.isEmpty ? nil : normalized
    }

    static func orderedExactModifierKeyCodes(_ exactModifierKeyCodes: Set<UInt16>) -> [UInt16] {
        modifierDisplayOrder.filter(exactModifierKeyCodes.contains)
    }

    static func exactModifierKeyCodesMatch(
        _ pressedModifierKeyCodes: Set<UInt16>,
        exactModifierKeyCodes: Set<UInt16>,
        permittedAdditionalExactMatchModifiers: ShortcutModifiers = []
    ) -> Bool {
        let normalizedExactModifierKeyCodes = normalizedExactModifierKeyCodes(exactModifierKeyCodes) ?? []

        for spec in modifierKeyCodeMatchSpecs {
            let exactKeyCodes = normalizedExactModifierKeyCodes.intersection(spec.keyCodes)
            let pressedKeyCodes = pressedModifierKeyCodes.intersection(spec.keyCodes)

            if exactKeyCodes.isEmpty {
                if !pressedKeyCodes.isEmpty && !permittedAdditionalExactMatchModifiers.contains(spec.logicalModifier) {
                    return false
                }
                continue
            }

            if exactKeyCodes.count == spec.keyCodes.count {
                guard !pressedKeyCodes.isEmpty,
                      pressedKeyCodes.isSubset(of: exactKeyCodes) else {
                    return false
                }
            } else if pressedKeyCodes != exactKeyCodes {
                return false
            }
        }

        return true
    }

    static func modifierDisplayNames(
        for modifiers: ShortcutModifiers,
        exactModifierKeyCodes: Set<UInt16>?
    ) -> [String] {
        let normalizedExactModifierKeyCodes = normalizedExactModifierKeyCodes(exactModifierKeyCodes) ?? []
        var names: [String] = []

        for spec in modifierDisplaySpecs {
            let exactKeyCodes = Set(spec.exactDisplayNames.map(\.0))
            let matchingExactKeyCodes = normalizedExactModifierKeyCodes.intersection(exactKeyCodes)
            if matchingExactKeyCodes.count == exactKeyCodes.count {
                names.append(spec.genericDisplayName)
                continue
            }

            let exactNames = spec.exactDisplayNames.compactMap { keyCode, displayName in
                normalizedExactModifierKeyCodes.contains(keyCode) ? displayName : nil
            }
            if !exactNames.isEmpty {
                names.append(contentsOf: exactNames)
            } else if modifiers.contains(spec.logicalModifier) {
                names.append(spec.genericDisplayName)
            }
        }

        return names
    }

    private static let modifierDisplayOrder: [UInt16] = [55, 54, 59, 62, 58, 61, 56, 60, 63]

    private static let modifierKeyCodeMatchSpecs: [(logicalModifier: ShortcutModifiers, keyCodes: Set<UInt16>)] = [
        (.command, [54, 55]),
        (.control, [59, 62]),
        (.option, [58, 61]),
        (.shift, [56, 60]),
        (.function, [63])
    ]

    private static let modifierDisplaySpecs: [(logicalModifier: ShortcutModifiers, genericDisplayName: String, exactDisplayNames: [(UInt16, String)])] = [
        (.command, "Cmd ⌘", [(55, "Cmd ⌘"), (54, "Right Cmd ⌘")]),
        (.control, "Ctrl ⌃", [(59, "Ctrl ⌃"), (62, "Right Ctrl ⌃")]),
        (.option, "Option ⌥", [(58, "Option ⌥"), (61, "Right Option ⌥")]),
        (.shift, "Shift ⇧", [(56, "Shift ⇧"), (60, "Right Shift ⇧")]),
        (.function, "Fn 🌐", [(63, "Fn 🌐")])
    ]
}

extension ShortcutPreset {
    static func matching(keyCode: UInt16) -> ShortcutPreset? {
        allCases.first { $0.binding.keyCode == keyCode }
    }
}
