import Foundation
import AVFoundation
import Speech
import os

enum SpeechEngineError: LocalizedError {
    case micDenied
    case noInputDevice
    case unsupportedLocale(String)
    case noAudioFormat
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .micDenied:
            return "Microphone access was denied. Enable it in System Settings > Privacy & Security > Microphone."
        case .noInputDevice:
            return "No audio input device is available."
        case .unsupportedLocale(let id):
            return "Speech recognition is not available for locale \(id) on this Mac."
        case .noAudioFormat:
            return "Could not negotiate a compatible audio format with the speech analyzer."
        case .engineFailed(let msg):
            return "Audio engine failed: \(msg)"
        }
    }
}

/// Wraps Apple's new on-device `SpeechAnalyzer` / `SpeechTranscriber` (macOS 26+).
@MainActor
final class SpeechEngine {

    /// Called with (text, isFinal). `text` for the non-final case is the
    /// current volatile segment only.
    var onResult: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var onStatus: ((String) -> Void)?
    /// Called from the audio thread with a smoothed 0...1 input level.
    var onAudioLevel: ((Float) -> Void)?

    /// Names and jargon the recognizer should expect. Passed to the analyzer
    /// as general contextual strings, which bias transcription without
    /// changing the model.
    var contextualStrings: [String] = []

    /// When true, the captured microphone audio is also written to a temporary
    /// WAV file so a remote provider can transcribe it after the session.
    var recordsAudio = false

    private let log = Logger(subsystem: "dev.harsh.quietspeech", category: "speech")
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var recordingWriter: RecordingWriter?

    private(set) var isRunning = false

    // MARK: - Permissions

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: - Model assets

    /// Ensures the on-device model for `locale` is installed, downloading if needed.
    ///
    /// Uses a throwaway module instance and deliberately does *not* keep it:
    /// a `SpeechModule` is bound to a single `SpeechAnalyzer` lifetime, so the
    /// module used for the asset query must not be handed to an analyzer, and
    /// a module that has already been analyzed must never be reused.
    func prepareModel(locale: Locale) async throws {
        let probe = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )

        if await SpeechTranscriber.supportedLocale(equivalentTo: locale) == nil {
            throw SpeechEngineError.unsupportedLocale(locale.identifier)
        }

        let status = await AssetInventory.status(forModules: [probe])
        if status != .installed {
            onStatus?("Downloading on-device model for \(locale.identifier)…")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                try await request.downloadAndInstall()
            }
            onStatus?("Model ready")
        }
    }

    // MARK: - Start / stop

    func start(locale: Locale) async throws {
        guard !isRunning else { return }

        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw SpeechEngineError.noInputDevice
        }

        try await prepareModel(locale: locale)

        // A brand-new module and analyzer for every recording session.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechEngineError.noAudioFormat
        }
        self.analyzerFormat = analyzerFormat
        self.converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let vocabulary = contextualStrings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try? await analyzer.setContext(context)
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.continuation = continuation

        if recordsAudio {
            prepareRecording(inputFormat: inputFormat)
        }

        // Capture locals so the realtime audio thread never touches actor state.
        let converter = self.converter
        let format = analyzerFormat
        let levelSink = self.onAudioLevel
        let recordingWriter = self.recordingWriter
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            if let levelSink {
                levelSink(SpeechEngine.level(of: buffer))
            }
            recordingWriter?.write(buffer)
            guard let converter,
                  let converted = SpeechEngine.convert(buffer, using: converter, to: format) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            discardRecording()
            throw SpeechEngineError.engineFailed(error.localizedDescription)
        }

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    self?.onResult?(text, result.isFinal)
                }
            } catch {
                self?.onError?(error)
            }
        }

        analysisTask = Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                self?.onError?(error)
            }
        }

        isRunning = true
    }

    @discardableResult
    func stop() async -> URL? {
        guard isRunning else { return nil }
        isRunning = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        continuation?.finish()
        continuation = nil
        converter = nil
        let recording = finishRecording()

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await analysisTask?.value
        await resultsTask?.value

        analysisTask = nil
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        return recording
    }

    func cancel() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        continuation?.finish()
        continuation = nil
        discardRecording()
        analysisTask?.cancel()
        resultsTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        analysisTask = nil
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        isRunning = false
    }

    // MARK: - Provider transcription audio

    private func prepareRecording(inputFormat: AVAudioFormat) {
        discardRecording()
        guard let writer = RecordingWriter(inputFormat: inputFormat) else { return }
        recordingWriter = writer
    }

    private func finishRecording() -> URL? {
        guard let writer = recordingWriter else { return nil }
        recordingWriter = nil
        writer.close()
        let url = writer.url

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              size > 44 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    private func discardRecording() {
        guard let writer = recordingWriter else { return }
        recordingWriter = nil
        writer.close()
        try? FileManager.default.removeItem(at: writer.url)
    }

    /// Writes microphone audio as a 16 kHz mono WAV for provider transcription.
    /// The file is closed explicitly so its WAV header is complete before upload.
    private final class RecordingWriter {
        let url: URL
        private var file: AVAudioFile?
        private let converter: AVAudioConverter
        private let format: AVAudioFormat

        init?(inputFormat: AVAudioFormat) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("quietspeech-\(UUID().uuidString).wav")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]

            do {
                let file = try AVAudioFile(
                    forWriting: url,
                    settings: settings,
                    commonFormat: .pcmFormatInt16,
                    interleaved: true
                )
                guard let converter = AVAudioConverter(from: inputFormat, to: file.processingFormat) else {
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                self.url = url
                self.file = file
                self.converter = converter
                self.format = file.processingFormat
            } catch {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
        }

        func write(_ buffer: AVAudioPCMBuffer) {
            guard let file,
                  let recorded = SpeechEngine.convert(buffer, using: converter, to: format) else {
                return
            }
            try? file.write(from: recorded)
        }

        func close() {
            file = nil
        }
    }

    /// Root-mean-square level of a buffer, mapped to 0...1 on a dB scale.
    /// Runs on the audio thread — no allocation.
    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        if let channels = buffer.floatChannelData {
            let data = channels[0]
            for i in 0..<frames {
                let sample = data[i]
                sum += sample * sample
            }
        } else if let channels = buffer.int16ChannelData {
            let data = channels[0]
            for i in 0..<frames {
                let sample = Float(data[i]) / 32768
                sum += sample * sample
            }
        } else {
            return 0
        }

        let rms = (sum / Float(frames)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (decibels + 60) / 60))
    }

    /// Converts a capture buffer into the analyzer's preferred format.
    /// Runs on the audio thread — must stay allocation-light and non-blocking.
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer,
                                using converter: AVAudioConverter,
                                to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var error: NSError?
        var supplied = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }

        if error != nil || output.frameLength == 0 { return nil }
        return output
    }
}
