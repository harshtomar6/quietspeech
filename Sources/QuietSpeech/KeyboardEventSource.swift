import CoreGraphics

/// App-generated typing must not suppress physical keyboard/mouse input or
/// feed back into another QuietSpeech shortcut listener.
enum KeyboardEventSource {
    static let marker: Int64 = 0x5153_5045_4543_4801

    static func make() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        source.userData = marker
        source.localEventsSuppressionInterval = 0
        let hardware: CGEventFilterMask = [
            .permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents
        ]
        source.setLocalEventsFilterDuringSuppressionState(hardware, state: .eventSuppressionStateSuppressionInterval)
        source.setLocalEventsFilterDuringSuppressionState(hardware, state: .eventSuppressionStateRemoteMouseDrag)
        return source
    }
}
