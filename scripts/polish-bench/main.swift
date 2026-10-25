import Foundation
import FoundationModels

// Runs captured dictations through AI polish with Apple Intelligence and
// scores the results, so a prompt change can be measured instead of guessed.
// Build and run with scripts/polish-bench/run.sh; see its header for options.

struct Capture: Decodable {
    let raw: String
    let app: String?
    let kind: String?
}

struct Outcome: Encodable {
    let app: String
    let profile: String
    let input: String
    let output: String?
    /// nil when the output would be inserted.
    let rejected: String?
    let error: String?
    let wordsDropped: Int
    let wordsAdded: Int
}

/// The capture records the app's name, not its bundle id.
func profile(forApp app: String) -> ContextProfile {
    switch app {
    case "Slack", "Messages", "Discord", "WhatsApp", "Telegram": return .chat
    case "Mail", "Spark", "Mimestream", "Outlook": return .email
    case "Notes", "TextEdit", "Pages", "Bear", "Obsidian", "Notion": return .document
    case "Code", "Cursor", "Xcode", "Windsurf", "Zed": return .code
    case "Terminal", "iTerm2", "Ghostty", "Warp": return .terminal
    default: return .generic
    }
}

func words(_ text: String) -> [String] {
    text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
}

/// The same session the app builds in AIService.completeOnDevice: the
/// instructions, then each example as an earlier exchange.
func session(_ variant: String, _ profile: ContextProfile) -> LanguageModelSession {
    let (system, examples): (String, [PolishPrompt.Example])
    switch variant {
    case "shipped": (system, examples) = (PolishPrompt.instructions(for: profile), PolishPrompt.examples)
    case "candidate": (system, examples) = (CandidatePrompt.instructions(for: profile), CandidatePrompt.examples)
    default: fatalError("unknown prompt \(variant); use shipped or candidate")
    }
    var entries: [Transcript.Entry] = [
        .instructions(Transcript.Instructions(segments: [.text(.init(content: system))], toolDefinitions: [])),
    ]
    for example in examples {
        entries.append(.prompt(Transcript.Prompt(segments: [.text(.init(content: example.text))])))
        entries.append(.response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: example.edited))])))
    }
    return LanguageModelSession(transcript: Transcript(entries: entries))
}

@main
struct PolishBench {
    static func main() async throws {
        let arguments = CommandLine.arguments.dropFirst()
        let variant = arguments.first ?? "shipped"
        let limit = arguments.dropFirst().first.flatMap(Int.init) ?? .max
        let capturePath = ProcessInfo.processInfo.environment["CAPTURE"]
            ?? NSHomeDirectory() + "/Library/Application Support/QuietSpeech/dictation-capture.jsonl"
        let outPath = ProcessInfo.processInfo.environment["OUT"] ?? "polish-\(variant).jsonl"

        guard SystemLanguageModel.default.isAvailable else {
            print("Apple Intelligence isn't available on this Mac.")
            exit(1)
        }

        let captures = try String(contentsOfFile: capturePath, encoding: .utf8)
            .split(separator: "\n")
            .compactMap { try? JSONDecoder().decode(Capture.self, from: Data($0.utf8)) }
            .filter { $0.kind == nil || $0.kind == "dictation" }

        var outcomes: [Outcome] = []
        var skipped = (code: 0, short: 0)
        let encoder = JSONEncoder()
        FileManager.default.createFile(atPath: outPath, contents: nil)
        let out = try FileHandle(forWritingTo: URL(fileURLWithPath: outPath))

        for capture in captures {
            guard outcomes.count < limit else { break }
            let app = capture.app ?? ""
            let profile = profile(forApp: app)
            if profile.isCodeLike { skipped.code += 1; continue }
            let local = RuleCleaner.clean(capture.raw, profile: profile)
            guard PolishGuard.shouldPolish(local) else { skipped.short += 1; continue }

            var output: String?
            var failure: String?
            do {
                // The same settings as AIService.completeOnDevice.
                let response = try await session(variant, profile).respond(
                    to: local,
                    options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 1_600)
                )
                output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                failure = String(describing: error).prefix(120).description
            }

            let source = Set(words(local))
            let result = Set(words(output ?? ""))
            let outcome = Outcome(
                app: app,
                profile: profile.rawValue,
                input: local,
                output: output,
                rejected: output.flatMap {
                    PolishGuard.rejection(polished: $0, original: local)
                        ?? (PolishPrompt.echoesExample($0, input: local) ? "echoed example" : nil)
                },
                error: failure,
                wordsDropped: output == nil ? 0 : source.subtracting(result).count,
                wordsAdded: output == nil ? 0 : result.subtracting(source).count
            )
            outcomes.append(outcome)
            try out.write(contentsOf: encoder.encode(outcome) + Data("\n".utf8))
            FileHandle.standardError.write(Data("\r\(outcomes.count) done".utf8))
        }
        try out.close()
        FileHandle.standardError.write(Data("\n".utf8))

        report(variant: variant, outcomes: outcomes, skipped: skipped, outPath: outPath)
    }

    static func report(variant: String, outcomes: [Outcome], skipped: (code: Int, short: Int), outPath: String) {
        let total = outcomes.count
        func pct(_ n: Int) -> String { total == 0 ? "-" : String(format: "%d (%.0f%%)", n, Double(n) * 100 / Double(total)) }

        let errors = outcomes.filter { $0.error != nil }
        let rejected = outcomes.filter { $0.rejected != nil }
        let accepted = outcomes.filter { $0.error == nil && $0.rejected == nil }
        let unchanged = accepted.filter { $0.output == $0.input }
        let lossy = accepted.filter { $0.wordsDropped > 0 }

        print("Prompt: \(variant)")
        print("Polished: \(total)   (skipped \(skipped.code) code/terminal, \(skipped.short) under 4 words)")
        print("Inserted: \(pct(accepted.count))")
        print("  unchanged: \(unchanged.count)   dropped a word: \(lossy.count)")
        print("Rejected by the safety check: \(pct(rejected.count))")
        for (reason, items) in Dictionary(grouping: rejected, by: { $0.rejected! }).sorted(by: { $0.value.count > $1.value.count }) {
            print("  \(reason): \(items.count)")
        }
        print("Model errors: \(pct(errors.count))")
        print("Results: \(outPath)")
    }
}
