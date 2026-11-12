import XCTest
@testable import QuietSpeech

final class MicrophoneControllerTests: XCTestCase {
    private let builtIn = AudioInputDevice(id: 1, uid: "built-in", name: "Mac Microphone")
    private let wireless = AudioInputDevice(id: 2, uid: "wireless-uid", name: "Wireless Mic")

    func testSystemDefaultResolvesInputRatherThanFirstAlphabeticalDevice() throws {
        let snapshot = AudioInputSnapshot(devices: [builtIn, wireless], defaultID: 2)
        XCTAssertEqual(try snapshot.resolve(""), wireless)
    }

    func testExplicitSelectionOverridesSystemDefault() throws {
        let snapshot = AudioInputSnapshot(devices: [builtIn, wireless], defaultID: 1)
        XCTAssertEqual(try snapshot.resolve(wireless.uid), wireless)
    }

    func testMissingExplicitDeviceNeverFallsBackToBuiltIn() {
        let snapshot = AudioInputSnapshot(devices: [builtIn], defaultID: 1)
        XCTAssertThrowsError(try snapshot.resolve(wireless.uid))
    }

    func testNoDefaultInputFailsEvenWhenOtherInputsExist() {
        XCTAssertThrowsError(try AudioInputSnapshot(devices: [wireless], defaultID: 0).resolve(""))
    }

    @MainActor
    func testSelectionSurvivesRelaunchWithStableUID() {
        withDefaults { defaults in
            let initial = AudioInputSnapshot(devices: [builtIn, wireless], defaultID: 1)
            let controller = MicrophoneController(defaults: defaults, observeHardware: false, readSnapshot: { initial })
            controller.select(wireless.uid)
            let reconnected = AudioInputDevice(id: 99, uid: wireless.uid, name: wireless.name)
            let restored = MicrophoneController(defaults: defaults, observeHardware: false, readSnapshot: {
                AudioInputSnapshot(devices: [self.builtIn, reconnected], defaultID: 1)
            })
            XCTAssertEqual(restored.selectedDevice, reconnected)
            XCTAssertEqual(restored.selectedUID, wireless.uid)
        }
    }

    @MainActor
    func testDisconnectRetainsChoiceAndReconnectRestoresIt() {
        withDefaults { defaults in
            var snapshot = AudioInputSnapshot(devices: [builtIn, wireless], defaultID: 1)
            let controller = MicrophoneController(defaults: defaults, observeHardware: false, readSnapshot: { snapshot })
            controller.select(wireless.uid)
            snapshot.devices = [builtIn]
            controller.refresh()
            XCTAssertTrue(controller.unavailable)
            XCTAssertEqual(controller.selectedUID, wireless.uid)
            XCTAssertTrue(controller.inputDescription.contains("Wireless Mic is disconnected"))
            snapshot.devices.append(AudioInputDevice(id: 42, uid: wireless.uid, name: wireless.name))
            controller.refresh()
            XCTAssertFalse(controller.unavailable)
            XCTAssertEqual(controller.selectedDevice?.id, 42)
        }
    }

    @MainActor
    func testDefaultFollowsChangesButExplicitSelectionStaysPinned() {
        withDefaults { defaults in
            var snapshot = AudioInputSnapshot(devices: [builtIn, wireless], defaultID: 1)
            let controller = MicrophoneController(defaults: defaults, observeHardware: false, readSnapshot: { snapshot })
            XCTAssertEqual(controller.selectedDevice, builtIn)
            snapshot.defaultID = 2
            controller.refresh()
            XCTAssertEqual(controller.selectedDevice, wireless)
            controller.select(builtIn.uid)
            controller.refresh()
            XCTAssertEqual(controller.selectedDevice, builtIn)
            controller.select("")
            XCTAssertEqual(controller.selectedDevice, wireless)
        }
    }

    @MainActor
    func testDisconnectedChoiceNameSurvivesRelaunch() {
        withDefaults { defaults in
            let controller = MicrophoneController(defaults: defaults, observeHardware: false, readSnapshot: {
                AudioInputSnapshot(devices: [self.wireless], defaultID: 2)
            })
            controller.select(wireless.uid)
            let restored = MicrophoneController(defaults: defaults, observeHardware: false, readSnapshot: {
                AudioInputSnapshot(devices: [], defaultID: 0)
            })
            XCTAssertTrue(restored.unavailable)
            XCTAssertEqual(restored.selectedName, wireless.name)
        }
    }

    @MainActor
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "MicrophoneControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
