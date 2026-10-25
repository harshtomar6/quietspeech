import AppKit
import AVFoundation

/// Thin wrapper over the TCC checks this app cares about.
enum Permissions {

    // MARK: Microphone

    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: Accessibility (posting ⌘V into other apps)
    //
    // This single grant covers both jobs:
    //   - posting the synthetic ⌘V that types the transcript (kTCCServicePostEvent)
    //   - the active activation event tap in ShortcutBackend (also kTCCServicePostEvent)
    //
    // A listen-only tap would instead demand kTCCServiceListenEvent (Input
    // Monitoring), a second permission for identical functionality.

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Raw AX trust value, used in diagnostics. Note that calling
    /// `AXIsProcessTrustedWithOptions(prompt:)` initialises the AX client, after
    /// which this can keep reporting the pre-grant value until the app is
    /// relaunched.
    static var accessibilityDebug: String {
        "trusted=\(AXIsProcessTrusted())"
    }

    static func promptAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: Deep links into System Settings

    static func openPrivacyPane(_ anchor: String) {
        let url = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}
