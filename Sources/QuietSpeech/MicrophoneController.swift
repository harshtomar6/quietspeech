import AVFoundation
import CoreAudio
import Observation

struct AudioInputDevice: Equatable, Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

struct AudioInputSnapshot: Equatable {
    var devices: [AudioInputDevice]
    var defaultID: AudioDeviceID

    func resolve(_ uid: String) throws -> AudioInputDevice {
        if uid.isEmpty, let device = devices.first(where: { $0.id == defaultID }) { return device }
        if !uid.isEmpty, let device = devices.first(where: { $0.uid == uid }) { return device }
        throw MicrophoneError.unavailable
    }
}

enum MicrophoneError: LocalizedError {
    case unavailable, routeChanged, invalidFormat

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The selected microphone is unavailable. Connect it or choose another input in Settings → Transcription."
        case .routeChanged:
            return "The microphone connection or audio format changed. Please check your input in Settings → Transcription and try again."
        case .invalidFormat:
            return "This microphone has no usable audio input. Choose another input in Settings → Transcription."
        }
    }
}

enum AudioInputHardware {
    static func snapshot() -> AudioInputSnapshot {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return AudioInputSnapshot(devices: [], defaultID: 0)
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty else { return AudioInputSnapshot(devices: [], defaultID: 0) }
        let status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return AudioInputSnapshot(devices: [], defaultID: 0) }
        let devices = ids.compactMap { id -> AudioInputDevice? in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        address.mSelector = kAudioHardwarePropertyDefaultInputDevice
        var defaultID: AudioDeviceID = 0
        size = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultID)
        return AudioInputSnapshot(devices: devices, defaultID: defaultID)
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage) == noErr else { return false }
        return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
            .contains { $0.mNumberChannels > 0 }
    }

    /// Route only this engine. Never change the Mac's default input device.
    @MainActor
    static func makeEngine(selectedUID: String) throws -> (AVAudioEngine, AudioInputDevice) {
        let device = try snapshot().resolve(selectedUID)
        let engine = AVAudioEngine()
        if engine.inputNode.auAudioUnit.deviceID != device.id {
            try engine.inputNode.auAudioUnit.setDeviceID(device.id)
        }
        try validate(engine, device: device)
        return (engine, device)
    }

    @MainActor
    static func validate(_ engine: AVAudioEngine, device: AudioInputDevice) throws {
        guard snapshot().devices.contains(where: { $0.uid == device.uid && $0.id == device.id }),
              engine.inputNode.auAudioUnit.deviceID == device.id else {
            throw MicrophoneError.routeChanged
        }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw MicrophoneError.invalidFormat }
    }

    @MainActor
    static func captureIsValid(_ engine: AVAudioEngine, device: AudioInputDevice, format: AVAudioFormat) -> Bool {
        // Core Audio also posts configuration notifications for benign setup
        // changes. Only interrupt capture if its actual input stopped or changed.
        guard engine.isRunning, engine.inputNode.outputFormat(forBus: 0) == format else { return false }
        do {
            try validate(engine, device: device)
            return true
        } catch { return false }
    }
}

/// Owns the Core Audio listener blocks so they can be removed without retaining the UI model.
private final class AudioInputObservation {
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(changed: @escaping () -> Void) {
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                    mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { _, _ in changed() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
                listeners.append((address, block))
            }
        }
    }

    deinit {
        for (var address, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }
}

@MainActor @Observable
final class MicrophoneController {
    private(set) var snapshot = AudioInputSnapshot(devices: [], defaultID: 0)
    private(set) var selectedUID: String
    private(set) var selectedName: String
    private(set) var isTesting = false
    private(set) var level: Float = 0
    private(set) var testMessage: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let readSnapshot: () -> AudioInputSnapshot
    @ObservationIgnored private var observation: AudioInputObservation?
    @ObservationIgnored private var testEngine: AVAudioEngine?
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?
    @ObservationIgnored private var testDeadline: Task<Void, Never>?
    @ObservationIgnored private var testGeneration = 0

    init(defaults: UserDefaults = .standard, observeHardware: Bool = true,
         readSnapshot: @escaping () -> AudioInputSnapshot = AudioInputHardware.snapshot) {
        self.defaults = defaults
        self.readSnapshot = readSnapshot
        selectedUID = defaults.string(forKey: "microphoneDeviceUID") ?? ""
        selectedName = defaults.string(forKey: "microphoneDeviceName") ?? "Selected microphone"
        refresh()
        if observeHardware {
            observation = AudioInputObservation { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    var selectedDevice: AudioInputDevice? { try? snapshot.resolve(selectedUID) }
    var unavailable: Bool { selectedDevice == nil }
    var inputDescription: String {
        if let selectedDevice { return "Input: \(selectedDevice.name)" }
        return selectedUID.isEmpty ? "No system input is available." : "\(selectedName) is disconnected. Reconnect it or choose another input."
    }

    func select(_ uid: String) {
        stopTest()
        selectedUID = uid
        selectedName = snapshot.devices.first { $0.uid == uid }?.name ?? "Selected microphone"
        defaults.set(uid, forKey: "microphoneDeviceUID")
        defaults.set(selectedName, forKey: "microphoneDeviceName")
        testMessage = nil
    }

    func refresh() {
        snapshot = readSnapshot()
        if !selectedUID.isEmpty, let device = selectedDevice { selectedName = device.name }
        if isTesting, selectedDevice?.id != testEngine?.inputNode.auAudioUnit.deviceID {
            stopTest()
            testMessage = MicrophoneError.routeChanged.localizedDescription
        }
    }

    func startTest() {
        stopTest()
        testMessage = nil
        do {
            let (engine, device) = try AudioInputHardware.makeEngine(selectedUID: selectedUID)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            let generation = testGeneration
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                let level = SpeechEngine.level(of: buffer)
                Task { @MainActor in
                    guard let self, self.isTesting, self.testGeneration == generation else { return }
                    self.level = level
                }
            }
            testEngine = engine
            do { try engine.start() } catch {
                stopTest()
                throw error
            }
            isTesting = true
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self, weak engine] _ in
                Task { @MainActor in
                    guard let self, let engine, self.isTesting, self.testGeneration == generation,
                          !AudioInputHardware.captureIsValid(engine, device: device, format: format) else { return }
                    self.stopTest()
                    self.testMessage = MicrophoneError.routeChanged.localizedDescription
                }
            }
            testDeadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.stopTest()
            }
        } catch { testMessage = error.localizedDescription }
    }

    func stopTest() {
        testGeneration &+= 1
        testDeadline?.cancel()
        testDeadline = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        testEngine?.stop()
        testEngine?.inputNode.removeTap(onBus: 0)
        testEngine = nil
        isTesting = false
        level = 0
    }
}
