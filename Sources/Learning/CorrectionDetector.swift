import Foundation

/// A word the user fixed after it was typed in: what QuietSpeech wrote, and
/// what the user changed it to.
public struct Correction: Hashable, Sendable {
    public let heard: String
    public let corrected: String
    /// Also worth a "heard → corrected" replacement. False when the heard form
    /// is an ordinary word that would be wrong to rewrite everywhere
    /// ("Korea" → "Kariya"); the corrected term then only goes to vocabulary.
    public let addsReplacement: Bool
    /// The names and jargon in the corrected text, for vocabulary. Counted on
    /// their own, because the recognizer rarely mishears a word the same way
    /// twice ("ERLMAP", then "LMAK", for "LLM").
    public let terms: [String]

    public init(heard: String, corrected: String, addsReplacement: Bool, terms: [String]) {
        self.heard = heard
        self.corrected = corrected
        self.addsReplacement = addsReplacement
        self.terms = terms
    }
}

/// Compares what was inserted with what the user left there, and keeps only
/// the edits that look like a misheard word being fixed. Rewording, deleting
/// and typing more are editing, not corrections, and are ignored.
public enum CorrectionDetector {

    /// Longest misheard phrase, in words, on either side of an edit.
    static let maxPhraseWords = 3
    /// Beyond this the user has rewritten the text, not corrected it.
    static let maxWords = 300

    public static func corrections(
        original: String,
        edited: String,
        isKnownWord: (String) -> Bool
    ) -> [Correction] {
        let a = tokens(in: original)
        let b = tokens(in: edited)
        guard !a.isEmpty, !b.isEmpty, a.count <= maxWords, b.count <= maxWords * 2 else { return [] }

        var found: [Correction] = []
        for hunk in hunks(a, b) {
            guard (1...maxPhraseWords).contains(hunk.removed.count),
                  (1...maxPhraseWords).contains(hunk.added.count),
                  let correction = correction(removed: hunk.removed, added: hunk.added, isKnownWord: isKnownWord),
                  !found.contains(correction) else { continue }
            found.append(correction)
        }
        return found
    }

    // MARK: Judging one edit

    static func correction(removed: [Token], added: [Token], isKnownWord: (String) -> Bool) -> Correction? {
        let heard = removed.map(\.text).joined(separator: " ")
        let corrected = added.map(\.text).joined(separator: " ")
        let heardKey = key(heard)
        let correctedKey = key(corrected)
        guard heardKey.count >= 2, correctedKey.count >= 2,
              correctedKey.contains(where: \.isLetter) else { return nil }

        if heardKey == correctedKey {
            if heard.lowercased() == corrected.lowercased() {
                // Only the case changed. Capitalizing a sentence opener is a
                // grammar fix; capitalizing a word mid-sentence names something.
                guard added.count == 1, !added[0].startsSentence,
                      corrected.contains(where: \.isUppercase) else { return nil }
                return Correction(heard: heard, corrected: corrected, addsReplacement: false, terms: [corrected])
            }
            // Spacing or punctuation: "quiet speech" → "QuietSpeech", "nodejs" → "Node.js".
            let terms = distinctiveTerms(added, isKnownWord: isKnownWord)
            guard !terms.isEmpty else { return nil }
            return Correction(heard: heard, corrected: corrected, addsReplacement: true, terms: terms)
        }

        let terms = distinctiveTerms(added, isKnownWord: isKnownWord)
        guard soundsAlike(heardKey, correctedKey), !terms.isEmpty else { return nil }

        // Rewriting a misspelling ("pria") or an odd phrase ("jet hub") is
        // safe everywhere. Rewriting a real word ("Korea") is not.
        let heardIsOdd = removed.count > 1 || removed.contains { !isKnownWord($0.text.lowercased()) }
        return Correction(heard: heard, corrected: corrected, addsReplacement: heardIsOdd, terms: terms)
    }

    /// The corrected words must be a name or jargon. If the user swaps one
    /// ordinary word for another ("their" → "there"), that's grammar, and
    /// learning it would make every later dictation worse.
    static func distinctiveTerms(_ words: [Token], isKnownWord: (String) -> Bool) -> [String] {
        words.filter { word in
            switch ScreenTerms.classify(word.text) {
            case .mixedCase, .acronym: return true
            case .capitalized: return !word.startsSentence || !isKnownWord(word.text.lowercased())
            case nil: return word.text.contains(where: \.isLetter) && !isKnownWord(word.text.lowercased())
            }
        }
        .map { singularAcronym($0.text) }
    }

    /// "APIs" → "API". The recognizer handles the plural once it knows the word.
    static func singularAcronym(_ word: String) -> String {
        guard word.count >= 3, word.hasSuffix("s"),
              word.dropLast().allSatisfy({ $0.isUppercase || $0.isNumber }) else { return word }
        return String(word.dropLast())
    }

    /// Close in spelling, or nearly the same consonants in the same order.
    /// The consonant check catches spoken acronyms, which the recognizer
    /// spells as it hears them ("ERLMAP" for "LLM API").
    static func soundsAlike(_ a: String, _ b: String) -> Bool {
        let distance = editDistance(Array(a), Array(b))
        if Double(distance) <= Double(max(a.count, b.count)) * 0.4 { return true }
        let sa = skeleton(a), sb = skeleton(b)
        guard sa.count >= 2, sb.count >= 2 else { return false }
        if sa == sb { return true }
        return min(sa.count, sb.count) >= 3 && editDistance(Array(sa), Array(sb)) <= 1
    }

    /// Lowercased letters and digits only.
    static func key(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Consonants with vowels, soft letters and repeats removed: "priya" → "pr".
    static func skeleton(_ key: String) -> String {
        var out = ""
        for character in key where !"aeiouyhw".contains(character) {
            if out.last != character { out.append(character) }
        }
        return out
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    // MARK: Word diff

    struct Token: Equatable {
        let text: String
        let startsSentence: Bool
    }

    struct Hunk {
        var removed: [Token] = []
        var added: [Token] = []
    }

    static func tokens(in text: String) -> [Token] {
        var out: [Token] = []
        var startsSentence = true
        for raw in text.split(whereSeparator: \.isWhitespace) {
            let word = Tokenizer.trimPunctuation(raw)
            if !word.isEmpty {
                out.append(Token(text: word, startsSentence: startsSentence))
            }
            if let last = raw.last, ".!?\n".contains(last) {
                startsSentence = true
            } else if !word.isEmpty {
                startsSentence = false
            }
        }
        return out
    }

    /// Runs of words removed from `a` and added in `b` between the words they
    /// share, from a longest-common-subsequence alignment. Words are compared
    /// exactly, so a change of case shows up as an edit.
    static func hunks(_ a: [Token], _ b: [Token]) -> [Hunk] {
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i].text == b[j].text
                    ? lcs[i + 1][j + 1] + 1
                    : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var hunks: [Hunk] = []
        var pending = Hunk()
        func flush() {
            if !pending.removed.isEmpty || !pending.added.isEmpty { hunks.append(pending) }
            pending = Hunk()
        }

        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, a[i].text == b[j].text {
                flush()
                i += 1; j += 1
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                pending.added.append(b[j]); j += 1
            } else {
                pending.removed.append(a[i]); i += 1
            }
        }
        flush()
        // A pure insertion or deletion isn't a correction.
        return hunks.filter { !$0.removed.isEmpty && !$0.added.isEmpty }
    }
}
