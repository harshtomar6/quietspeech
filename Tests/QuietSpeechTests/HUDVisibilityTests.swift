import AppKit
import XCTest
@testable import QuietSpeech

final class HUDVisibilityTests: XCTestCase {
    @MainActor
    private func makePanel() -> NSPanel {
        _ = NSApplication.shared
        let panel = NSPanel(
            contentRect: NSRect(x: 40, y: 40, width: 20, height: 20),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        return panel
    }

    @MainActor
    func testPreviousHideCannotDismissNewPresentation() async throws {
        let hud = HUDController()
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        hud.present(panel)
        try await Task.sleep(for: .milliseconds(250))

        hud.hide()
        try await Task.sleep(for: .milliseconds(40))
        hud.present(panel)
        // Wait past both animations: an old hide must not order out the
        // panel after the next dictation has already presented it.
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.01)
    }

    @MainActor
    func testFinalHideStillDismissesPanelAfterRepeatedPresentations() async throws {
        let hud = HUDController()
        let panel = makePanel()
        defer { panel.orderOut(nil) }
        for _ in 0..<3 {
            hud.present(panel)
            hud.hide()
        }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(panel.isVisible)
    }
}
