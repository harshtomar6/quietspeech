import AVFoundation
import Foundation

/// A dictation saved by the app (Settings › Privacy › Save audio clips):
/// `<id>.wav` with `<id>.json` beside it. The reference you type with
/// `run.sh label` goes in `<id>.ref.txt`.
struct Clip: Decodable {
    let id: String
    let app: String
    let locale: String
    let language: String
    /// Apple's live transcript, before cleanup.
    let apple: String
    /// The hints Apple was given: your vocabulary plus names on screen.
    let vocabulary: [String]

    var directory: URL!

    enum CodingKeys: String, CodingKey { case id, app, locale, language, apple, vocabulary }

    var audioURL: URL { directory.appendingPathComponent("\(id).wav") }
    var referenceURL: URL { directory.appendingPathComponent("\(id).ref.txt") }

    var reference: String? {
        (try? String(contentsOf: referenceURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var seconds: Double {
        guard let file = try? AVAudioFile(forReading: audioURL) else { return 0 }
        return Double(file.length) / file.fileFormat.sampleRate
    }

    static func load(from directory: URL) -> [Clip] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Clip? in
                guard var clip = try? JSONDecoder().decode(Clip.self, from: Data(contentsOf: url)) else { return nil }
                clip.directory = directory
                return FileManager.default.fileExists(atPath: clip.audioURL.path) ? clip : nil
            }
            .sorted { $0.id < $1.id }
    }

    func delete() {
        for url in [audioURL, referenceURL, directory.appendingPathComponent("\(id).json")] {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Transcripts are kept under `results/<recognizer>/` so a rerun only
/// transcribes new clips. `--fresh` clears them.
struct ResultCache {
    let directory: URL

    struct Entry: Codable {
        let text: String
        /// Wall-clock seconds the recognizer took; nil for the live baseline.
        let seconds: Double?
    }

    private func url(_ recognizer: String, _ clip: Clip) -> URL {
        directory.appendingPathComponent("results/\(recognizer)/\(clip.id).json")
    }

    func get(_ recognizer: String, _ clip: Clip) -> Entry? {
        try? JSONDecoder().decode(Entry.self, from: Data(contentsOf: url(recognizer, clip)))
    }

    func set(_ entry: Entry, _ recognizer: String, _ clip: Clip) {
        let url = url(recognizer, clip)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entry).write(to: url)
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("results"))
    }
}
