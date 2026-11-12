import SwiftUI
import AppKit

/// Shared by first-run setup and Transcription settings.
struct MicrophoneSettings: View {
    @Bindable var model: AppModel
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        SettingsGroup("Microphone", icon: "mic", note: "Connect wireless or USB microphones to your Mac first. This choice applies only to QuietSpeech.") {
            SettingsRow("Input device", subtitle: model.microphone.inputDescription) {
                Picker("Input device", selection: Binding(
                    get: { model.microphone.selectedUID },
                    set: { model.microphone.select($0) }
                )) {
                    Text("System Default").tag("")
                    ForEach(model.microphone.snapshot.devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                    if !model.microphone.selectedUID.isEmpty, model.microphone.unavailable {
                        Text("\(model.microphone.selectedName) (Disconnected)")
                            .tag(model.microphone.selectedUID)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                .disabled(model.microphoneControlsDisabled)
            }

            SettingsDivider()

            SettingsRow("Input level", subtitle: model.microphone.isTesting
                        ? "Speak now. Testing stops after 15 seconds; no audio is saved."
                        : "Test your microphone before dictating.") {
                HStack(spacing: 10) {
                    ProgressView(value: Double(model.microphone.level))
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                        .accessibilityLabel("Microphone input level")
                    Button(model.microphone.isTesting ? "Stop Test" : "Test Mic") {
                        if model.microphone.isTesting {
                            model.microphone.stopTest()
                        } else {
                            testTask?.cancel()
                            testTask = Task { @MainActor in
                                let granted = await Permissions.requestMicrophone()
                                model.refreshPermissions()
                                guard !Task.isCancelled, !model.microphoneControlsDisabled else { return }
                                if granted { model.microphone.startTest() }
                            }
                        }
                    }
                    .disabled(model.microphoneControlsDisabled || model.microphone.unavailable)
                }
            }

            if let message = model.microphone.testMessage {
                SettingsNote(message, icon: "exclamationmark.triangle")
                    .padding(12)
            }

            SettingsDivider()
            SettingsRow("Missing a microphone?", subtitle: "Check that macOS recognizes it under Sound → Input.") {
                Button("Open Sound Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .onAppear { model.microphone.refresh() }
        .onDisappear {
            testTask?.cancel()
            model.microphone.stopTest()
        }
    }
}
