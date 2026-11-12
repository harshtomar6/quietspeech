import Darwin
import Foundation
import os

/// Owns the media interruption across recording and transcription. Resume
/// requires a confirmed playing state and the same paused player at finish.
@MainActor
final class MediaPlaybackController {
    private let sendCommand: @Sendable (Int32) -> Bool
    struct PlaybackState: Sendable, Equatable, Decodable {
        let playerID: Int32
        let isPlaying: Bool
    }

    typealias ReadPlayback = @Sendable (@escaping @Sendable (PlaybackState?) -> Void) -> Void
    private let readPlayback: ReadPlayback
    private let timeout: TimeInterval
    private let stateTimeout: TimeInterval
    private let queue = DispatchQueue(label: "dev.harsh.quietspeech.media", qos: .userInitiated)
    private let gate = SessionGate()
    private var session: Int?
    private var resumePlayer: Int32?
    private var resumingSession: Int?
    private let log = Logger(subsystem: "dev.harsh.quietspeech", category: "media")

    init(
        timeout: TimeInterval = 0.15,
        stateTimeout: TimeInterval = 0.5,
        readPlayback: @escaping ReadPlayback = { SystemMediaPlaybackState.read($0) },
        sendCommand: @escaping @Sendable (Int32) -> Bool = { SystemMediaCommands.send($0) }
    ) {
        self.timeout = timeout
        self.stateTimeout = stateTimeout
        self.sendCommand = sendCommand
        self.readPlayback = readPlayback
    }

    @discardableResult
    func pauseIfEnabled(_ enabled: Bool, session: Int) async -> Bool {
        self.session = session
        gate.set(session)
        // A new recording can supersede a transcription that still owns the
        // pause. Carry that ownership forward even though audio is now quiet.
        guard enabled else { return false }
        let before = await playbackState()
        guard self.session == session else { return false }
        let sent = await request(1, session: session) // kMRPause; never toggle.
        guard self.session == session else { return sent }
        if sent, let before, before.isPlaying { resumePlayer = before.playerID }
        log.info("pause request sent=\(sent) resumeArmed=\(self.resumePlayer != nil)")
        return sent
    }

    @discardableResult
    func resumeIfNeeded(for session: Int) async -> Bool {
        guard self.session == session, resumingSession != session else { return false }
        guard let player = resumePlayer else {
            self.session = nil
            gate.set(nil)
            return false
        }
        resumingSession = session
        let current = await playbackState()
        guard self.session == session else {
            if resumingSession == session { resumingSession = nil }
            return false
        }
        var sent = false
        if let current, current.playerID == player, !current.isPlaying {
            sent = await request(0, session: session) // kMRPlay; never toggle.
        }
        if self.session == session {
            self.session = nil
            resumePlayer = nil
            gate.set(nil)
        }
        if resumingSession == session { resumingSession = nil }
        log.info("resume request sent=\(sent)")
        return sent
    }

    private func playbackState() async -> PlaybackState? {
        await TimedCallback.run(timeout: stateTimeout, fallback: nil, start: readPlayback)
    }

    private func request(_ command: Int32, session: Int) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        return await TimedCallback.run(timeout: timeout, fallback: false) { finish in
            queue.async { [sendCommand, gate] in
                guard gate.matches(session), ProcessInfo.processInfo.systemUptime < deadline else {
                    finish(false)
                    return
                }
                finish(sendCommand(command))
            }
        }
    }

    private final class SessionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var session: Int?

        func set(_ session: Int?) {
            lock.lock()
            self.session = session
            lock.unlock()
        }

        func matches(_ session: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return self.session == session
        }
    }
}

private enum SystemMediaCommands {
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool
    // Resolve the system sender at runtime and keep the framework loaded
    // for the lifetime of its function pointer.
    private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY | RTLD_LOCAL
    )
    private static let send: SendCommand? = load("MRMediaRemoteSendCommand")

    private static func load<Function>(_ name: String) -> Function? {
        guard let framework, let symbol = dlsym(framework, name) else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }

    static func send(_ command: Int32) -> Bool {
        send?(command, nil) ?? false
    }

}

private enum SystemMediaPlaybackState {
    // Query only the selected app's PID and playing/paused state. macOS's
    // script host can read these without Automation or Audio Capture grants;
    // direct MediaRemote reads from the signed app can return empty state.
    private static let script = #"""
    ObjC.import('Foundation');
    function run() {
        const media = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
        if (!media.load) return 'null';
        const request = $.NSClassFromString('MRNowPlayingRequest');
        const before = Number(request.localNowPlayingPlayerPath.client.processIdentifier);
        const state = Number(request.localPlaybackState);
        const after = Number(request.localNowPlayingPlayerPath.client.processIdentifier);
        if (!(before > 0) || before !== after || (state !== 1 && state !== 2)) return 'null';
        return JSON.stringify({playerID: before, isPlaying: state === 1});
    }
    """#

    static func read(_ finish: @escaping @Sendable (MediaPlaybackController.PlaybackState?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-l", "JavaScript", "-e", script]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0, data.count <= 256 else {
                    finish(nil)
                    return
                }
                finish(try? JSONDecoder().decode(MediaPlaybackController.PlaybackState.self, from: data))
            }
            do { try process.run() } catch { finish(nil); return }
            // Bound the helper's lifetime as well as the caller's wait.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.45) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
}
