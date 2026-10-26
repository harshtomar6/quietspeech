import AVFoundation
import Foundation
import Speech
import Voz

/// One way of turning a clip into text. Each one is scored against the
/// reference you typed with `run.sh label`.
protocol Recognizer {
    var name: String { get }
    /// Shown under the results table.
    var summary: String { get }
    /// False when this recognizer can't run the clip, such as a language Voz
    /// doesn't cover. The clip is then left out of its score.
    func supports(_ clip: Clip) -> Bool
    func transcribe(_ clip: Clip) async throws -> String
}

/// What the app actually heard while you spoke: Apple's live, streaming
/// transcript with your vocabulary and on-screen names as hints.
struct AppleLive: Recognizer {
    let name = "apple-live"
    let summary = "Apple, live in the app (the baseline)"
    func supports(_ clip: Clip) -> Bool { true }
    func transcribe(_ clip: Clip) async throws -> String { clip.apple }
}

/// Apple's SpeechAnalyzer on the saved file, without streaming.
struct AppleFile: Recognizer {
    let hints: Bool
    var name: String { hints ? "apple" : "apple-nohints" }
    var summary: String { "Apple, on the saved file" + (hints ? ", with the same hints" : ", no hints") }

    func supports(_ clip: Clip) -> Bool { true }

    func transcribe(_ clip: Clip) async throws -> String {
        let locale = Locale(identifier: clip.locale)
        let transcriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: []
        )
        if await AssetInventory.status(forModules: [transcriber]) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if hints, !clip.vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = clip.vocabulary
            try await analyzer.setContext(context)
        }
        let collect = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        let file = try AVAudioFile(forReading: clip.audioURL)
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        return try await collect.value
    }
}

/// Desert Ant Labs' Voz. The first run downloads its model (about 470 MB)
/// from Hugging Face.
final class VozRecognizer: Recognizer {
    let hints: Bool
    private var model: Voz?

    init(hints: Bool) { self.hints = hints }

    var name: String { hints ? "voz" : "voz-nohints" }
    var summary: String { "Desert Ant Voz" + (hints ? ", with the same hints" : ", no hints") }

    func supports(_ clip: Clip) -> Bool {
        Voz.supportedLanguages.contains(clip.language)
    }

    func transcribe(_ clip: Clip) async throws -> String {
        if model == nil {
            if !Voz.isDownloaded() {
                print("Downloading the Voz model (first run only)…")
                try await Voz.download { progress in
                    FileHandle.standardError.write(Data(String(format: "\r  %3.0f%%", progress.fraction * 100).utf8))
                }
                FileHandle.standardError.write(Data("\n".utf8))
            }
            model = try await Voz()
        }
        let result = hints && !clip.vocabulary.isEmpty
            ? try await model!.transcribe(clip.audioURL, vocabulary: clip.vocabulary)
            : try await model!.transcribe(clip.audioURL)
        return result.text
    }
}

func allRecognizers() -> [Recognizer] {
    [AppleLive(), AppleFile(hints: true), AppleFile(hints: false), VozRecognizer(hints: true), VozRecognizer(hints: false)]
}
