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
struct WhisprProtoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        // The app is menu-bar only (LSUIElement), so this is the one window:
        // setup on first run, the settings form on every run after.
        Window("Whispr Proto", id: "settings") {
            Group {
                if model.onboardingCompleted {
                    SettingsView(model: model)
                } else {
                    OnboardingView(model: model)
                }
            }
        }
        .defaultSize(width: 560, height: 640)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(model.onboardingCompleted ? .suppressed : .presented)

        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.isRecording ? "waveform" : "mic.fill")
        }
    }
}

private struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(model.isRecording ? "Stop dictation" : "Start dictation") {
            model.toggleDictation()
        }

        Divider()

        Text("Activation: \(model.shortcutConfiguration.summary)")

        Divider()

        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quit Whispr Proto") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
