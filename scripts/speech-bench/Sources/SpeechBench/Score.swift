import Foundation

/// Word error rate, the usual measure for speech recognition: the fewest
/// words to substitute, insert or delete to turn the output into the
/// reference, divided by the reference's length.
enum Score {
    /// Fillers are left out on both sides, since cleanup removes them anyway.
    static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "erm", "er", "ah", "hmm", "mm"]

    /// Lowercased words without punctuation, so only the words are scored.
    /// Hyphens are dropped, so "stand-up" and "standup" match.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "-", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty && !fillers.contains($0) }
    }

    static func errors(_ hypothesis: [String], _ reference: [String]) -> Int {
        guard !reference.isEmpty else { return hypothesis.count }
        var previous = Array(0...hypothesis.count)
        for (i, word) in reference.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: hypothesis.count)
            for (j, other) in hypothesis.enumerated() {
                current[j + 1] = word == other
                    ? previous[j]
                    : 1 + min(previous[j], previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[hypothesis.count]
    }

    /// The hints that were actually said, and how many of them the output
    /// got right. Names and jargon are where recognizers differ most, and a
    /// few wrong names hide inside an otherwise low error rate.
    static func terms(_ vocabulary: [String], hypothesis: [String], reference: [String]) -> (said: Int, right: Int) {
        var said = 0, right = 0
        for term in Set(vocabulary.map(words)) where !term.isEmpty {
            guard contains(reference, term) else { continue }
            said += 1
            if contains(hypothesis, term) { right += 1 }
        }
        return (said, right)
    }

    private static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard phrase.count <= words.count else { return false }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }
}
