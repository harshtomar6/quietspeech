import SwiftUI

/// Shared by Activation settings and the first-run key chooser.
struct ToggleActivationSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SettingsRow("Tap to Toggle", subtitle: detail) {
                Picker("Activate with", selection: Binding(
                    get: { model.shortcutConfiguration.toggleActivationMethod },
                    set: { model.setToggleActivationMethod($0) }
                )) {
                    ForEach(ToggleActivationMethod.allCases, id: \.self) { method in
                        Text(method.title).tag(method)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 190)
            }

            if model.shortcutConfiguration.toggleActivationMethod == .shortcut {
                SettingsDivider()
                SettingsRow("Toggle shortcut", subtitle: "Press once to start, again to stop.") {
                    ShortcutRecorder(
                        binding: Binding(
                            get: { model.shortcutConfiguration.toggle },
                            set: { model.setBinding($0, for: .toggle) }
                        ),
                        onCaptureStateChanged: { model.setShortcutCapture($0) },
                        onCapture: {
                            model.applyActivation()
                            model.refreshPermissions()
                        }
                    )
                }
            }
        }
    }

    private var detail: String {
        guard model.shortcutConfiguration.toggleActivationMethod == .doubleTapHold else {
            return "Use a separate shortcut for hands-free dictation."
        }
        let hold = model.shortcutConfiguration.hold
        guard !hold.isDisabled else {
            return "Set a Hold to Talk key to enable double-tap."
        }
        return "Double-tap \(hold.displayName) to start; tap once to stop. Holding it still works."
    }
}
