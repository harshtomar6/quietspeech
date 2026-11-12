import Darwin
import Foundation
import os

/// Sends a pause-only request to macOS's current media player. A paused
/// player stays paused; no play/pause key event or automatic resume is used.
struct MediaPlaybackController {
    private let sendCommand: @Sendable (Int32) -> Bool
    private let timeout: TimeInterval
    private let log = Logger(subsystem: "dev.harsh.quietspeech", category: "media")

    init(
        timeout: TimeInterval = 0.15,
        sendCommand: @escaping @Sendable (Int32) -> Bool = { SystemMediaCommands.send($0) }
    ) {
        self.timeout = timeout
        self.sendCommand = sendCommand
    }

    @MainActor
    @discardableResult
    func pauseIfEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let sent = await TimedCallback.run(timeout: timeout, fallback: false) { finish in
            DispatchQueue.global(qos: .userInitiated).async { [sendCommand] in
                // A busy queue must not pause media long after dictation starts.
                guard ProcessInfo.processInfo.systemUptime < deadline else {
                    finish(false)
                    return
                }
                finish(sendCommand(1)) // kMRPause; 2 would toggle playback.
            }
        }
        log.info("pause request sent=\(sent)")
        return sent
    }
}

private enum SystemMediaCommands {
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool

    // There is no public API for sending a pause to another app. Resolve the
    // system function at runtime, so an unavailable API remains a no-op.
    // Keep the framework loaded for the lifetime of this function pointer.
    private static let send: SendCommand? = {
        guard let framework = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY | RTLD_LOCAL
        ) else { return nil }
        guard let symbol = dlsym(framework, "MRMediaRemoteSendCommand") else {
            dlclose(framework)
            return nil
        }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    static func send(_ command: Int32) -> Bool {
        send?(command, nil) ?? false
    }
}
