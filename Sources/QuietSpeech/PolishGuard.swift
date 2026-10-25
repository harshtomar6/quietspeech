import Foundation

/// Decides when AI polish is worth running and whether its output is still
/// the speaker's text. Small chat-tuned models (Apple's on-device one in
/// particular) tend to answer a dictated question or invent a whole email from
/// a single word; when that happens the local cleanup is inserted instead.
enum PolishGuard {
    /// Below this, there is nothing for polish to improve and the model has
    /// too little to anchor on.
    static let minimumWords = 4

    /// Openers a model uses when replying rather than rewriting.
    private static let answerOpeners = [
        "sure", "yes", "no", "certainly", "of course", "absolutely",
        "here is", "here's", "i can", "i'd be happy", "great question",
    ]

    static func shouldPolish(_ text: String) -> Bool {
        words(in: text).count >= minimumWords
    }

    /// Returns nil when `polished` is acceptable, otherwise a short reason
    /// for the log.
    static func rejection(polished: String, original: String) -> String? {
        let source = words(in: original)
        let output = words(in: polished)
        guard !source.isEmpty, !output.isEmpty else { return "empty" }

        if output.count > source.count * 13 / 10 + 3 {
            return "longer"
        }

        let sourceSet = Set(source)
        let outputSet = Set(output)
        // Grammar fixes add a word or two ("why it reports" -> "why does it
        // report"), which is a large share of a short sentence.
        let added = output.filter { !sourceSet.contains($0) }.count
        if added > max(2, output.count * 35 / 100) {
            return "new words"
        }
        let kept = Double(source.filter { outputSet.contains($0) }.count) / Double(source.count)
        if kept < 0.5 {
            return "dropped words"
        }

        let originalLower = original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let polishedLower = polished.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let opener = answerOpeners.first(where: { startsWithPhrase(polishedLower, $0) }),
           !startsWithPhrase(originalLower, opener) {
            return "answer opener"
        }

        // Only a closing question counts; a filler "Hmm?" may be dropped.
        if originalLower.hasSuffix("?"), !polished.contains("?") {
            return "question answered"
        }

        if polished.contains("["), !original.contains("[") {
            return "placeholder"
        }

        return nil
    }

    private static func startsWithPhrase(_ text: String, _ phrase: String) -> Bool {
        guard text.hasPrefix(phrase) else { return false }
        let rest = text.dropFirst(phrase.count)
        return rest.first.map { !$0.isLetter && !$0.isNumber } ?? true
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
