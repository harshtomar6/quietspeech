import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: only steal focus when the setup window is about to show.
        let done = UserDefaults.standard.object(forKey: "onboardingCompleted") as? Bool ?? false
        if !done { NSApp.activate(ignoringOtherApps: true) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the setup window must not quit the app.
        false
    }
}

@main
struct QuietSpeechApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var updater = UpdateController()

    var body: some Scene {
        // The app is menu-bar only (LSUIElement), so this is the one window:
        // setup on first run, the settings form on every run after.
        Window("QuietSpeech", id: "settings") {
            Group {
                if model.onboardingCompleted {
                    SettingsView(model: model)
                } else {
                    OnboardingView(model: model)
                }
            }
        }
        .defaultSize(width: 560, height: 640)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.onboardingCompleted ? .suppressed : .presented)

        Window("Welcome to QuietSpeech", id: "onboarding") {
            OnboardingWindowContent(model: model)
        }
        .defaultSize(width: 620, height: 580)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        MenuBarExtra {
            MenuContent(model: model, updater: updater)
        } label: {
            Image(nsImage: BrandMark.image())
                .renderingMode(.template)
                .foregroundStyle(model.isRecording ? Color(nsColor: .systemRed) : Color.primary)
                .accessibilityLabel(model.isRecording ? "QuietSpeech, recording" : "QuietSpeech")
        }
    }
}

private struct OnboardingWindowContent: View {
    @Bindable var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        OnboardingView(model: model) {
            dismissWindow(id: "onboarding")
        }
    }
}

private struct MenuContent: View {
    @Bindable var model: AppModel
    var updater: UpdateController
    @Environment(\.openWindow) private var openWindow

    private var primaryActionTitle: String {
        if !model.license.canUseApp { return "Activate QuietSpeech…" }
        return model.isRecording ? "Stop dictation" : "Start dictation"
    }

    private var contextSummary: String {
        switch model.contextMode {
        case .auto:
            return model.hasContext ? "Context: Auto \u{00b7} \(model.activeProfile.label)" : "Context: Auto"
        default:
            return "Context: \(model.contextMode.profile?.label ?? model.activeProfile.label)"
        }
    }

    var body: some View {
        Button(primaryActionTitle) {
            if model.license.canUseApp {
                model.toggleDictation()
            } else {
                LicenseWindowController.shared.present(model: model)
            }
        }

        Divider()

        Text("Activation: \(model.shortcutConfiguration.summary)")
        Text(contextSummary)
        if model.aiGenerateReady {
            Text("Generate: say “\(model.generateTriggerDisplay)” then an instruction")
        }
        if !model.license.canUseApp {
            Text("License: \(model.license.overviewStatus)")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("License…") {
            model.requestedSettingsPane = .license
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        if model.onboardingCompleted {
            Button("Show Onboarding…") {
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Button("Check for Updates…") {
            updater.checkForUpdates()
        }

        Button("Quit QuietSpeech") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
