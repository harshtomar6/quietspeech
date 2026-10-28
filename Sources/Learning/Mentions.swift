import Foundation

/// Turns a spoken mention into "@Name" for chat apps such as Slack, where a
/// pasted "@Name" becomes a real mention when it matches a member.
///
/// "at" is an everyday word, so a plain "at Priya" only counts when Priya is
/// a known name (on screen or in the user's vocabulary) and the "at" opens a
/// sentence or clause, or follows a cue like "hey" or "cc". "meet at Google"
/// and "look at Priya's PR" stay as they are. "at sign Priya" and "at the
/// rate Priya" are explicit and always make a mention.
///
/// The recognizer often hears a quick "at" as "add" (or "ad"), so those count
/// too, except where "add" is the verb: "Add Priya to the channel" stays.
public enum Mentions {

    public static func apply(to text: String, names: [String]) -> String {
        let known = mentionableNames(names)
        var result = explicit(text, known: known)
        if !known.isEmpty {
            result = implicit(result, known: known)
            result = detached(result, known: known)
        }
        return result
    }

    /// "@ Priya", as a recognizer or AI polish may write it, is not a mention
    /// in Slack. Joined only for known names.
    private static func detached(_ text: String, known: [String]) -> String {
        let alternation = known.map(pattern(for:)).joined(separator: "|")
        let regex = try! NSRegularExpression(
            pattern: #"@\s+("# + alternation + ")" + nameEnd,
            options: [.caseInsensitive]
        )
        return replace(text, regex) { groups in
            "@" + canonical(groups[0], known: known)
        }
    }

    /// Names worth mentioning: capitalized words with a lowercase letter, so
    /// acronyms (API, LLM) and stray symbols never become mentions. Longest
    /// first, so "Priya Shah" wins over "Priya".
    static func mentionableNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { name in
                guard let first = name.first, first.isUppercase,
                      name.contains(where: \.isLowercase),
                      name.count >= 2,
                      name.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" || $0 == "\u{2019}" })
                else { return false }
                return seen.insert(name.lowercased()).inserted
            }
            .sorted { $0.count > $1.count }
    }

    /// Clause openers and cue words after which "at <name>" is a mention.
    private static let lead = #"(^|[.!?;:,]\s+|\b(?:hey|hi|hello|cc|ping|thanks|thank you)\s+)"#
    /// The name must end there: not "Priyanka", not "Priya's".
    private static let nameEnd = #"(?![\p{L}\p{N}'\x{2019}])"#
    /// "at", or "add"/"ad" as the recognizer often hears it.
    private static let at = #"(at|add?)"#
    /// Captures the word after the name, without consuming it.
    private static let nextWord = #"(?=(?:\s+([\p{L}]+))?)"#
    /// Words after "add <name>" that show "add" is the verb.
    private static let addContinuations: Set<String> = [
        "to", "into", "in", "on", "onto", "as", "and", "or", "back", "too", "also",
        "here", "there", "again", "from", "for", "with",
    ]

    private static func isMisheardAt(_ word: String) -> Bool {
        word.lowercased() != "at"
    }

    private static func implicit(_ text: String, known: [String]) -> String {
        let alternation = known.map(pattern(for:)).joined(separator: "|")
        let regex = try! NSRegularExpression(
            pattern: lead + at + #"\s+("# + alternation + ")" + nameEnd + nextWord,
            options: [.caseInsensitive, .anchorsMatchLines]
        )
        return replace(text, regex) { groups in
            if isMisheardAt(groups[1]), addContinuations.contains(groups[3].lowercased()) {
                return nil
            }
            return groups[0] + "@" + canonical(groups[2], known: known)
        }
    }

    /// "at sign" takes any word; "at the rate" (but never "at the rate of")
    /// takes a known or capitalized one, since "at the rate inflation…" is
    /// still English. Heard as "add", both need a known or capitalized name,
    /// so "add sign in" stays.
    private static func explicit(_ text: String, known: [String]) -> String {
        let alternation = known.map(pattern(for:)).joined(separator: "|")
        let word = #"[\p{L}][\p{L}\p{N}._-]*"#
        let target = alternation.isEmpty ? "(\(word))" : "(\(alternation)|\(word))"
        let regex = try! NSRegularExpression(
            pattern: #"\b"# + at + #"\s+(sign|the\s+rate)\s+(?!of\b)"# + target + nameEnd,
            options: [.caseInsensitive]
        )
        return replace(text, regex) { groups in
            let name = canonical(groups[2], known: known)
            let isKnown = known.contains { $0.lowercased() == name.lowercased() }
            let anyWord = groups[1].lowercased() == "sign" && !isMisheardAt(groups[0])
            if anyWord || isKnown || name.first?.isUppercase == true {
                return "@" + name
            }
            return nil
        }
    }

    private static func pattern(for name: String) -> String {
        name.split(separator: " ")
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: #"\s+"#)
    }

    /// The spelling from the name list, whatever casing the recognizer used.
    private static func canonical(_ spoken: String, known: [String]) -> String {
        let normalized = spoken.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        return known.first { $0.lowercased() == normalized } ?? spoken
    }

    /// Replaces each match with `transform(captureGroups)`; nil keeps the match.
    private static func replace(_ text: String, _ regex: NSRegularExpression,
                                _ transform: ([String]) -> String?) -> String {
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let groups = (1..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += transform(groups) ?? ns.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
