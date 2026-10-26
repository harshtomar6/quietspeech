import Foundation

// Compares speech recognizers on your own dictations. See run.sh for usage.

let usage = """
Usage: scripts/speech-bench/run.sh <command>

  label                    play each new clip and type what you actually said
  score [names] [--fresh]  transcribe the labeled clips and compare
                           names: comma-separated, default all of
                           \(allRecognizers().map(\.name).joined(separator: ", "))
                           --fresh: transcribe again instead of using saved results

Clips come from ~/Library/Application Support/QuietSpeech/speech-clips
(set CLIPS to use another folder).
"""

let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLIPS"]
    ?? NSHomeDirectory() + "/Library/Application Support/QuietSpeech/speech-clips")

func ask(_ prompt: String) -> String? {
    print(prompt, terminator: "")
    fflush(stdout)
    return readLine()
}

func quoted(_ text: String) -> String { "\u{201C}\(text)\u{201D}" }

// MARK: - label

/// Plays a clip in the background; the next clip stops it.
final class Player {
    private var process: Process?

    func play(_ url: URL) {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        process.arguments = [url.path]
        try? process.run()
        self.process = process
    }

    func stop() {
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }
}

/// Opens the text in $EDITOR (nano if unset) and returns what was saved.
func edit(_ text: String) -> String? {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("speech-bench-\(UUID().uuidString).txt")
    try? text.write(to: file, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: file) }
    let editor = Process()
    editor.executableURL = URL(fileURLWithPath: "/bin/zsh")
    editor.arguments = ["-c", "${EDITOR:-nano} \"$0\"", file.path]
    try? editor.run()
    editor.waitUntilExit()
    return (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func label() {
    let clips = Clip.load(from: directory)
    let pending = clips.filter { $0.reference == nil }
    guard !pending.isEmpty else {
        print(clips.isEmpty
            ? "No clips yet. Turn on Settings › Privacy › Save audio clips and dictate as usual."
            : "All \(clips.count) clips are labeled. Run: scripts/speech-bench/run.sh score")
        return
    }
    print("""
    \(pending.count) clips to label. Listen, then type exactly what you said.
    Leave out ums and uhs; punctuation and capitals don't count.

    """)
    let player = Player()
    defer { player.stop() }
    let cache = ResultCache(directory: directory)
    var done = 0

    clipLoop: for (index, clip) in pending.enumerated() {
        print("[\(index + 1)/\(pending.count)] \(clip.app.isEmpty ? "?" : clip.app) · \(String(format: "%.1f", clip.seconds)) s")
        print("  Apple heard: \(quoted(clip.apple))")
        // Other recognizers' guesses, from an earlier score, can help with a
        // word Apple missed.
        for recognizer in allRecognizers() where recognizer.name != "apple-live" {
            if let other = cache.get(recognizer.name, clip)?.text, Score.words(other) != Score.words(clip.apple) {
                print("  \(recognizer.name): \(quoted(other))")
            }
        }
        player.play(clip.audioURL)
        while true {
            guard let answer = ask("  Enter: Apple is right · type the text · e: edit · r: replay · s: skip · x: delete clip · q: quit\n  > ") else {
                break clipLoop
            }
            let reference: String?
            switch answer.trimmingCharacters(in: .whitespaces) {
            case "": reference = clip.apple
            case "e": reference = edit(clip.apple)
            case "r": player.play(clip.audioURL); continue
            case "s": reference = nil
            case "x": clip.delete(); reference = nil
            case "q": break clipLoop
            case let typed: reference = typed
            }
            if let reference, !reference.isEmpty {
                try? reference.write(to: clip.referenceURL, atomically: true, encoding: .utf8)
                done += 1
            }
            print("")
            break
        }
    }
    print("Labeled \(done). Run: scripts/speech-bench/run.sh score")
}

// MARK: - score

struct Tally {
    var clips = 0
    var errors = 0
    var words = 0
    var termsSaid = 0
    var termsRight = 0
    var audioSeconds = 0.0
    var runSeconds = 0.0
    var failures = 0

    var errorRate: String {
        words == 0 ? "-" : String(format: "%.1f%%", Double(errors) * 100 / Double(words))
    }
    var termRate: String {
        termsSaid == 0 ? "-" : "\(termsRight)/\(termsSaid) (\(termsRight * 100 / termsSaid)%)"
    }
    var speed: String {
        runSeconds == 0 ? "live" : String(format: "%.0f× realtime", audioSeconds / runSeconds)
    }
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func score(_ arguments: [String]) async {
    let fresh = arguments.contains("--fresh")
    let names = arguments.first { !$0.hasPrefix("--") }?.split(separator: ",").map(String.init)
    let recognizers = allRecognizers().filter { names?.contains($0.name) ?? true }
    if let names, recognizers.count != names.count {
        print("Unknown recognizer in \(names.joined(separator: ",")).\n\n\(usage)")
        exit(2)
    }

    let clips = Clip.load(from: directory).filter { $0.reference != nil }
    guard !clips.isEmpty else {
        print("No labeled clips. Run: scripts/speech-bench/run.sh label")
        return
    }
    let cache = ResultCache(directory: directory)
    if fresh { cache.clear() }

    var tallies: [String: Tally] = [:]
    /// Per clip, each recognizer's word errors, for the report.
    var rows: [(clip: Clip, outputs: [(name: String, text: String, errors: Int)])] = []

    for (index, clip) in clips.enumerated() {
        FileHandle.standardError.write(Data("\rTranscribing \(index + 1)/\(clips.count)…".utf8))
        let reference = Score.words(clip.reference!)
        var outputs: [(name: String, text: String, errors: Int)] = []
        for recognizer in recognizers where recognizer.supports(clip) {
            var tally = tallies[recognizer.name, default: Tally()]
            var entry = cache.get(recognizer.name, clip)
            if entry == nil {
                let started = Date()
                do {
                    let text = try await recognizer.transcribe(clip)
                    let seconds = recognizer is AppleLive ? nil : Date().timeIntervalSince(started)
                    entry = .init(text: text, seconds: seconds)
                    cache.set(entry!, recognizer.name, clip)
                } catch {
                    tally.failures += 1
                    tallies[recognizer.name] = tally
                    FileHandle.standardError.write(Data("\n\(recognizer.name) failed on \(clip.id): \(error)\n".utf8))
                    continue
                }
            }
            let hypothesis = Score.words(entry!.text)
            let errors = Score.errors(hypothesis, reference)
            let terms = Score.terms(clip.vocabulary, hypothesis: hypothesis, reference: reference)
            tally.clips += 1
            tally.errors += errors
            tally.words += reference.count
            tally.termsSaid += terms.said
            tally.termsRight += terms.right
            if let seconds = entry!.seconds {
                tally.audioSeconds += clip.seconds
                tally.runSeconds += seconds
            }
            tallies[recognizer.name] = tally
            outputs.append((recognizer.name, entry!.text, errors))
        }
        rows.append((clip, outputs))
    }
    FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))

    print("\(clips.count) labeled clips, \(String(format: "%.0f", clips.reduce(0) { $0 + $1.seconds })) s of audio\n")
    print(pad("Recognizer", 15) + pad("Clips", 7) + pad("Word errors", 13) + pad("Hint words right", 19) + "Speed")
    for recognizer in recognizers {
        guard let tally = tallies[recognizer.name] else { continue }
        print(pad(recognizer.name, 15) + pad("\(tally.clips)", 7) + pad(tally.errorRate, 13) + pad(tally.termRate, 19) + tally.speed
            + (tally.failures > 0 ? "  (\(tally.failures) failed)" : ""))
    }
    print("")
    for recognizer in recognizers where tallies[recognizer.name] != nil {
        print("  \(pad(recognizer.name, 13)) \(recognizer.summary)")
    }

    // Head to head with the live baseline, on the clips both ran.
    if recognizers.contains(where: { $0.name == "apple-live" }) {
        print("")
        for recognizer in recognizers where recognizer.name != "apple-live" && tallies[recognizer.name] != nil {
            var better = 0, worse = 0
            for row in rows {
                guard let base = row.outputs.first(where: { $0.name == "apple-live" }),
                      let other = row.outputs.first(where: { $0.name == recognizer.name }) else { continue }
                if other.errors < base.errors { better += 1 } else if other.errors > base.errors { worse += 1 }
            }
            print("  \(pad(recognizer.name, 13)) vs apple-live: better on \(better), worse on \(worse), same on the rest")
        }
    }

    // Every clip where the recognizers disagree, worst first, to read
    // through what each one got wrong.
    var report = "# Speech bench\n\nWord errors per clip; only clips where the recognizers differ.\n"
    for row in rows.sorted(by: { ($0.outputs.map(\.errors).max() ?? 0) > ($1.outputs.map(\.errors).max() ?? 0) })
    where Set(row.outputs.map(\.errors)).count > 1 {
        report += "\n## \(row.clip.id) · \(row.clip.app)\n\n- **reference**: \(row.clip.reference!)\n"
        for output in row.outputs {
            report += "- **\(output.name)** (\(output.errors)): \(output.text)\n"
        }
    }
    let reportURL = directory.appendingPathComponent("report.md")
    try? report.write(to: reportURL, atomically: true, encoding: .utf8)
    print("\nPer-clip differences: \(reportURL.path)")
}

// MARK: - main

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "label": label()
case "score": await score(Array(arguments.dropFirst()))
default: print(usage)
}
