import Foundation

/// Picks the names and jargon out of text that is on screen when a dictation
/// starts, so the recognizer can expect them for that one dictation.
///
/// Common words are left out on purpose: the recognizer already knows them,
/// and a long list of hints makes the useful ones weaker.
public enum ScreenTerms {

    /// - Parameters:
    ///   - text: Whatever was read from the focused window.
    ///   - isKnownWord: Whether a lowercased word is in the dictionary.
    ///   - limit: The most terms to return, best first.
    public static func extract(
        from text: String,
        isKnownWord: (String) -> Bool,
        limit: Int = 40
    ) -> [String] {
        var scores: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        /// Forms seen capitalized inside running prose, so a word that only
        /// opens a sentence ("Thanks") or sits in a Title Case label
        /// ("Created", "Channel Info") isn't mistaken for a name.
        var midSentence: Set<String> = []
        var order = 0

        for sentence in sentences(in: text) {
            let words = Tokenizer.words(in: sentence).compactMap(withoutContraction)
            let isProse = words.count >= 3
                && words.dropFirst().filter { $0.first?.isUppercase == true }.count * 2 < words.count - 1
            for (index, word) in words.enumerated() {
                guard let kind = classify(word) else { continue }
                if index > 0, isProse { midSentence.insert(word) }

                let score: Int
                switch kind {
                case .mixedCase: score = 3          // QuietSpeech, iPhone
                case .acronym: score = 1            // API, SDK
                case .capitalized:
                    // Capitalized and not a dictionary word: almost always a name.
                    score = isKnownWord(word.lowercased()) ? 1 : 3
                }

                scores[word, default: 0] += score
                if firstSeen[word] == nil {
                    firstSeen[word] = order
                    order += 1
                }
            }
        }

        let candidates = scores.keys.filter { word in
            switch classify(word) {
            case .capitalized:
                // A dictionary word only counts as a name when it's capitalized
                // mid-sentence ("ask Polar about it").
                let lowered = word.lowercased()
                if calendarWords.contains(lowered) { return false }
                return midSentence.contains(word) || !isKnownWord(lowered)
            case .mixedCase, .acronym:
                return true
            case nil:
                return false
            }
        }

        return candidates
            .sorted {
                let a = scores[$0, default: 0], b = scores[$1, default: 0]
                return a != b ? a > b : firstSeen[$0, default: 0] < firstSeen[$1, default: 0]
            }
            .prefix(limit)
            .map { $0 }
    }

    enum Kind { case capitalized, mixedCase, acronym }

    /// Always capitalized, and never misheard, so they'd only crowd the list.
    static let calendarWords: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december", "today", "tomorrow", "yesterday",
    ]

    /// "Priya's" counts as "Priya"; other contractions ("I'm", "We'll") are
    /// never names.
    static func withoutContraction(_ word: String) -> String? {
        let normalized = word.replacingOccurrences(of: "\u{2019}", with: "'")
        guard normalized.contains("'") else { return word }
        guard normalized.hasSuffix("'s"), normalized.filter({ $0 == "'" }).count == 1 else { return nil }
        return String(normalized.dropLast(2))
    }

    static func classify(_ word: String) -> Kind? {
        let letters = word.filter(\.isLetter)
        guard letters.count >= 2, let first = word.first, first.isLetter || first.isNumber else { return nil }
        // Only scripts with case carry the signal this relies on.
        guard letters.allSatisfy({ $0.isUppercase || $0.isLowercase }) else { return nil }

        let uppers = letters.filter(\.isUppercase).count
        if uppers == letters.count {
            return letters.count <= 5 ? .acronym : nil
        }
        if uppers == 0 { return nil }
        let rest = word.dropFirst()
        if rest.contains(where: \.isUppercase) {
            return .mixedCase
        }
        return first.isUppercase ? .capitalized : nil
    }

    static func sentences(in text: String) -> [Substring] {
        text.split(whereSeparator: { ".!?\n\r•·|—".contains($0) })
    }
}

enum Tokenizer {
    /// Words with surrounding punctuation trimmed. Apostrophes, hyphens and
    /// dots inside a word are kept, so "O'Neil", "e-mail" and "Node.js" stay whole.
    static func words(in text: some StringProtocol) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || "/()[]{}<>\"“”‘,;:".contains($0) })
            .map { trimPunctuation($0) }
            .filter { !$0.isEmpty }
    }

    static func trimPunctuation(_ word: some StringProtocol) -> String {
        var scalars = Substring(word)
        while let first = scalars.first, !first.isLetter, !first.isNumber { scalars = scalars.dropFirst() }
        while let last = scalars.last, !last.isLetter, !last.isNumber { scalars = scalars.dropLast() }
        return String(scalars)
    }
}
