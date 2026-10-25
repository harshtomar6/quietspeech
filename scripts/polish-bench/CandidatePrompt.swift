import Foundation

/// A prompt to compare against the shipped one (`PolishPrompt`). It starts
/// as a copy; edit it, run `run.sh candidate`, and move it into
/// `PolishPrompt` when it scores better.
enum CandidatePrompt {
    static let examples = PolishPrompt.examples

    static func instructions(for profile: ContextProfile) -> String {
        PolishPrompt.instructions(for: profile)
    }
}
