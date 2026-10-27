import Foundation

/// Turns a spoken mention into "@Name" for chat apps such as Slack, where a
/// pasted "@Name" becomes a real mention when it matches a member.
///
/// "at" is an everyday word, so a plain "at Priya" only counts when Priya is
/// a known name (on screen or in the user's vocabulary) and the "at" opens a
/// sentence or clause, or follows a cue like "hey" or "cc". "meet at Google"
/// and "look at Priya's PR" stay as they are. "at sign Priya" and "at the
/// rate Priya" are explicit and always make a mention.
public enum Mentions {

    public static func apply(to text: String, names: [String]) -> String {
        let known = mentionableNames(names)
        var result = explicit(text, known: known)
        if !known.isEmpty {
            result = implicit(result, known: known)
        }
        return result
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

    private static func implicit(_ text: String, known: [String]) -> String {
        let alternation = known.map(pattern(for:)).joined(separator: "|")
        let regex = try! NSRegularExpression(
            pattern: lead + #"at\s+("# + alternation + ")" + nameEnd,
            options: [.caseInsensitive, .anchorsMatchLines]
        )
        return replace(text, regex) { groups in
            groups[0] + "@" + canonical(groups[1], known: known)
        }
    }

    /// "at sign" takes any word; "at the rate" (but never "at the rate of")
    /// takes a known or capitalized one, since "at the rate inflation…" is
    /// still English.
    private static func explicit(_ text: String, known: [String]) -> String {
        let alternation = known.map(pattern(for:)).joined(separator: "|")
        let word = #"[\p{L}][\p{L}\p{N}._-]*"#
        let target = alternation.isEmpty ? "(\(word))" : "(\(alternation)|\(word))"
        let regex = try! NSRegularExpression(
            pattern: #"\bat\s+(sign|the\s+rate)\s+(?!of\b)"# + target + nameEnd,
            options: [.caseInsensitive]
        )
        return replace(text, regex) { groups in
            let name = canonical(groups[1], known: known)
            let isKnown = known.contains { $0.lowercased() == name.lowercased() }
            if groups[0].lowercased() == "sign" || isKnown || name.first?.isUppercase == true {
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
