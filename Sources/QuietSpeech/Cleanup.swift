import Foundation

// MARK: - Rule-based cleanup

/// Deterministic, instant, offline cleanup. Every transformation is grammar or
/// a token list, so it cannot invent text: its worst case is a clumsy edit,
/// never words the speaker did not say.
enum RuleCleaner {

    static func clean(_ raw: String, replacements: [WordReplacement] = [],
                      profile: ContextProfile = .generic) -> String {
        let endsPunctuated = raw.last.map { ".,!?…。".contains($0) } ?? false
        var text = collapse(raw)
        text = spokenPunctuation(text, profile: profile)
        text = stripFillers(text)
        text = applyCorrections(text)
        text = applyReplacements(text, replacements)
        text = tidy(text, endsPunctuated: endsPunctuated, profile: profile)
        return applySpokenFormatting(text, profile: profile)
    }

    // MARK: Spoken punctuation

    private static let pathToken = #"[A-Za-z0-9_][A-Za-z0-9_./-]*"#

    /// Any token that is a common function word is never joined across a path
    /// connector, so "the dot product" cannot become "the.product".
    private static let functionWords: Set<String> = [
        "the", "a", "an", "of", "is", "are", "was", "were", "be", "been",
        "in", "on", "at", "to", "for", "and", "or", "but", "with", "this",
        "that", "these", "those", "it", "its", "as", "by", "has", "have",
        "had", "do", "does", "did", "we", "i", "you", "they", "he", "she",
        "not", "no", "all", "any", "our", "your", "their", "my", "his",
        "her", "from", "into",
    ]

    private static func spokenPunctuation(_ input: String, profile: ContextProfile) -> String {
        // Addresses need the "dot" in the domain while it is still a word.
        var text = profile == .email ? emailAddresses(input) : input

        text = replace(text, "\\b(?:dash|double|hyphen)[ -]dash\\s+([A-Za-z0-9][A-Za-z0-9_-]*)", "--$1")

        // Symbols first, so "fat arrow" cannot be read by the path pass as
        // "fat<arrow>open".
        if profile.usesCodeSymbols {
            text = commandFlags(text)
            text = applyCodeSymbols(text)
        }

        let symbols = ["slash": "/", "underscore": "_", "dot": ".", "arrow": "->"]
        if let regex = try? NSRegularExpression(
            pattern: "(\(pathToken))\\s+(slash|underscore|dot|arrow)\\s+(\(pathToken))",
            options: [.caseInsensitive]) {
            for _ in 0..<8 {
                let next = replaceMapping(text, regex) { group in
                    guard !functionWords.contains(group[0].lowercased()) else {
                        return group[0] + " " + group[1] + " " + group[2]
                    }
                    return group[0] + (symbols[group[1].lowercased()] ?? group[1]) + group[2]
                }
                if next == text { break }
                text = next
            }
        }
        return text
    }

    /// "john at gmail dot com" → john@gmail.com. Runs before the path pass,
    /// which would otherwise consume "gmail dot com" on its own.
    private static func emailAddresses(_ input: String) -> String {
        // A stopword before "at" is prose, not an address: "email me at john
        // dot smith at gmail dot com" must pick the second "at".
        replace(input,
                #"(?<![\p{L}\p{N}._%+-])(?!(?:me|it|him|her|them|us|you|this|that|there|here|email|mail|send|write|to|look|stay|be|is|was|were|are)\b)([A-Za-z0-9._%+-]+)\s+at\s+([A-Za-z0-9-]+)\s+dot\s+([A-Za-z]{2,})(?![\p{L}\p{N}])"#,
                "$1@$2.$3")
    }

    /// Symbols that are only sane when the destination is code. Longest-first
    /// so "double equals" wins over "equals".
    private static let codeSymbolTable: [(String, String)] = [
        ("triple equals", "==="),
        ("double equals", "=="),
        ("not equals", "!="),
        ("double ampersand", "&&"),
        ("double pipe", "||"),
        ("fat arrow", "=>"),
        ("open curly brace", "{"),
        ("close curly brace", "}"),
        ("open square bracket", "["),
        ("close square bracket", "]"),
        ("open parenthesis", "("),
        ("close parenthesis", ")"),
        ("left brace", "{"),
        ("right brace", "}"),
        ("left bracket", "["),
        ("right bracket", "]"),
        ("left paren", "("),
        ("right paren", ")"),
        ("open brace", "{"),
        ("close brace", "}"),
        ("open bracket", "["),
        ("close bracket", "]"),
        ("open paren", "("),
        ("close paren", ")"),
        ("semicolon", ";"),
        ("double quote", "\""),
        ("single quote", "'"),
        ("exclamation mark", "!"),
        ("question mark", "?"),
        ("dollar sign", "$"),
        ("percent sign", "%"),
        ("at sign", "@"),
        ("backslash", "\\"),
        ("forward slash", "/"),
        ("backtick", "`"),
        ("ampersand", "&"),
        ("asterisk", "*"),
        ("caret", "^"),
        ("tilde", "~"),
        ("colon", ":"),
        ("equals", "="),
        ("hyphen", "-"),
        ("comma", ","),
        ("pipe", "|"),
        ("hash sign", "#"),
        ("pound sign", "#"),
        ("bang", "!"),
    ]

    private static func applyCodeSymbols(_ input: String) -> String {
        var text = input
        for (phrase, symbol) in codeSymbolTable.sorted(by: { $0.0.count > $1.0.count }) {
            let body = phrase.split(separator: " ")
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"\s+"#)
            let pattern = #"(?<![\p{L}\p{N}])"# + body + #"(?![\p{L}\p{N}])"#
            text = replaceLiteral(text, pattern, symbol)
        }
        return text
    }

    // MARK: Filler

    private static let fillerWord = #"(?:umm|uhh|mmm|hmm|erm|euh|um|uh|er|ah|eh|उम|えーと|えっと)"#

    private static func stripFillers(_ input: String) -> String {
        // A Latin comma may be swallowed on either side of a hesitation; the
        // ideographic comma only on the trailing side, since it separates
        // real clauses. "I mean" is deliberately absent: it is a revision
        // marker, and stripping it here would glue the two clauses together
        // before applyCorrections could resolve the revision.
        var text = replace(input, "[,]?\\s*\\b\(fillerWord)\\b\\s*[,、]?\\s*", " ")
        text = replace(text, ",\\s*(?:like|you know)\\s*,", "")
        return text
    }

    // MARK: Self-correction

    private static let markerWords =
        #"scratch that|wait,?\s+i mean|i meant|no wait|actually no|no actually|sorry no|no,?\s+scratch that|make that|i mean|actually|sorry|wait|no"#

    private static let pronouns: Set<String> = [
        "it's", "its", "it", "i'll", "i", "let's", "lets", "we", "you", "they", "he", "she",
    ]

    private static let determiners: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those", "my", "your", "our", "their", "his", "her",
    ]

    /// Units that pair with a number, so "at 4 PM, no, at 5 PM" drops "4 PM"
    /// rather than leaving "at 4" to collide with the replacement.
    private static let units: Set<String> = [
        "pm", "am", "hours", "hrs", "minutes", "seconds", "baje", "bje",
    ]

    /// Verbs and auxiliaries, including romanised Hindi ones. A revision that
    /// would leave one of these dangling is a new clause, not a swapped tail:
    /// "cancel kar do, actually kal rakho" has to keep "kar do".
    private static let auxiliaries: Set<String> = [
        "do", "does", "did", "done", "kar", "karo", "karna", "kare", "kiya",
        "hai", "hain", "tha", "thi", "hoga", "hogi", "likho", "likha", "bhej",
        "bhejo", "rakho", "rakh", "raha", "rahi", "karte", "karta", "karti", "jao",
    ]

    /// Prepositions whose re-use signals a swapped phrase rather than a new
    /// clause: "send it to Priya, I mean, to Ankit" re-says the phrase the
    /// preposition introduces.
    private static let prepositions: Set<String> = [
        "to", "at", "on", "in", "for", "with", "from", "into", "by", "about",
        "over", "under", "near", "after", "before", "between", "through",
    ]

    private static func applyCorrections(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b(?:" + markerWords + ")\\b", options: [.caseInsensitive]) else { return input }
        var text = input
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text),
                  let revised = resolveCorrection(text, range) else { continue }
            text = revised
        }
        return text
    }

    /// A revision is only recognised after a comma or a finished sentence;
    /// without that guard "I'll wait outside." collapses to "Outside."
    private static func resolveCorrection(_ text: String, _ range: Range<String.Index>) -> String? {
        let before = String(text[text.startIndex..<range.lowerBound])
        let after = String(text[range.upperBound...]).drop { " ,、。".contains($0) }
        let head = before.trimmingCharacters(in: .whitespaces)
        var tail = String(after).trimmingCharacters(in: .whitespaces)

        guard !head.isEmpty, !tail.isEmpty else { return nil }
        guard ",.!?".contains(head.last ?? " ") else { return nil }
        guard let firstWord = words(tail).first else { return nil }

        let headWords = words(head), tailWords = words(tail)
        let repeatsOpening = tailWords.count >= 2 && headWords.count >= 2
            && tailWords[0] == headWords[0] && tailWords[1] == headWords[1]
        // "bhej do usko, wait, Priya ko bhej do": the revision re-uses the head's
        // opening verb pair at its end, so it replaces the whole head.
        let repeatsClosing = tailWords.count >= 3 && headWords.count >= 3
            && tailWords.suffix(2).elementsEqual(headWords.prefix(2))
        let restartsSentence = ".,!?".contains(head.last ?? " ") && pronouns.contains(firstWord)
        if repeatsOpening || repeatsClosing || restartsSentence { return tail }

        var stem = head
        if ".,!?".contains(head.last ?? " ") {
            while let last = stem.last, ".,!?".contains(last) { stem.removeLast() }
        }

        guard let stemLastWord = words(stem).last else { return nil }
        if auxiliaries.contains(stemLastWord) { return stem + ", " + tail }

        // The revision re-opens the same preposition, so the phrase hanging off
        // it is the part being re-said: "send it to Priya, I mean, to Ankit"
        // replaces "to Priya" with "to Ankit". Anchoring on the last such
        // preposition keeps any earlier phrase intact.
        if prepositions.contains(firstWord), let cut = lastWordBoundary(of: firstWord, in: stem) {
            let prefix = String(stem[stem.startIndex..<cut]).trimmingCharacters(in: .whitespaces)
            return prefix.isEmpty ? tail : prefix + " " + tail
        }

        let stemWords = words(stem)
        let timePair = stemWords.count >= 2 && units.contains(stemWords[stemWords.count - 1])
            && stemWords[stemWords.count - 2].allSatisfy { $0.isNumber }

        // Only a revision that clearly re-says the same phrase replaces it: a
        // swapped word ("on the left, I mean right"), a swapped time
        // ("at 4 PM, no, at 5 PM") or a determiner phrase of the same shape
        // ("the two o'clock slot, no, the three o'clock slot"). After a
        // finished sentence the tail simply takes over ("I'll send it
        // tomorrow. Sorry, the day after tomorrow."). Mid-sentence, anything
        // else is a fresh clause, so the stem is kept whole and separated by a
        // comma rather than glued on: "add the button to the header, wait, add
        // it to the footer" must not read "add the button to the add it".
        var kept = stem
        var separator = " "
        if timePair {
            kept = dropLastWord(dropLastWord(stem))
        } else if head.last.map({ ".!?".contains($0) }) == true || tailWords.count <= 2 {
            kept = dropLastWord(stem)
        } else if determiners.contains(firstWord),
                  let regex = try? NSRegularExpression(
                      pattern: "\\b(?:the|a|an|this|that|these|those|my|your|our|their|his|her)\\b",
                      options: [.caseInsensitive]),
                  let last = regex.matches(in: stem, range: NSRange(stem.startIndex..., in: stem)).last,
                  let lastRange = Range(last.range, in: stem),
                  words(String(stem[lastRange.lowerBound...])).count >= tailWords.count {
            kept = String(stem[stem.startIndex..<lastRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else {
            separator = ", "
        }

        // "Forward it to Priya, actually, to Dev" -> "to Dev", not "to to Dev".
        if let keptLast = words(kept).last, let tailFirst = words(tail).first, keptLast == tailFirst,
           let stripped = tail.range(of: #"^\S+\s*"#, options: .regularExpression) {
            tail = String(tail[stripped.upperBound...])
        }
        guard !tail.isEmpty else { return kept }
        return kept.isEmpty ? tail : kept + separator + tail
    }

    /// Start of the last whole-word occurrence of `word` in `text`.
    private static func lastWordBoundary(of word: String, in text: String) -> String.Index? {
        guard let regex = try? NSRegularExpression(
            pattern: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b",
            options: [.caseInsensitive]),
            let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
            let range = Range(match.range, in: text) else { return nil }
        return range.lowerBound
    }

    private static func dropLastWord(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespaces)
        while let last = text.last, ".,!?、。".contains(last) { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        guard let space = text.lastIndex(of: " ") else { return "" }
        return String(text[..<space])
    }

    // MARK: Word replacements

    /// Swaps personal vocabulary in one pass. Phrases are matched whole-word
    /// and longest-first, so "Whispr Flow" wins over "Flow", and the pass can
    /// never cascade a replacement into another one.
    static func applyReplacements(_ input: String, _ replacements: [WordReplacement]) -> String {
        let pairs = replacements
            .filter(\.isUsable)
            .map { (heard: $0.heard.trimmingCharacters(in: .whitespacesAndNewlines),
                    replacement: $0.replacement.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .sorted { $0.heard.count > $1.heard.count }
        guard !pairs.isEmpty else { return input }

        // A phrase may start or end with a symbol ("C++", ".NET"), so plain
        // \b is too blunt; guard on letters and digits instead.
        let pattern = pairs
            .map { #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: $0.heard) + #"(?![\p{L}\p{N}])"# }
            .joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }

        var lookup: [String: String] = [:]
        for pair in pairs {
            lookup[pair.heard.lowercased()] = pair.replacement
        }

        var out = ""
        var cursor = input.startIndex
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)) {
            guard let range = Range(match.range, in: input) else { continue }
            out += input[cursor..<range.lowerBound]
            let heard = String(input[range])
            let replacement = lookup[heard.lowercased()] ?? heard
            out += matchCase(of: replacement, like: heard)
            cursor = range.upperBound
        }
        out += input[cursor...]
        return out
    }

    /// "Github" spoken at the start of a sentence should not be rewritten to a
    /// lowercase "github" just because the replacement is lowercase.
    private static func matchCase(of replacement: String, like heard: String) -> String {
        guard let source = heard.first, let target = replacement.first,
              source.isUppercase, target.isLowercase else { return replacement }
        return target.uppercased() + replacement.dropFirst()
    }

    // MARK: Spoken formatting

    /// Explicit layout commands. Unlike filler removal these are opt-in by
    /// being said, so they still run when cleanup is switched off.
    static func applySpokenFormatting(_ input: String, profile: ContextProfile = .generic) -> String {
        let commands: [(String, String)] = [
            (#"\b(?:new|next)\s+paragraph(?:\s+break)?\b[.,!?]?"#, "\n\n"),
            (#"\bparagraph\s+break\b[.,!?]?"#, "\n\n"),
            (#"\b(?:new|next)\s+line\b[.,!?]?"#, "\n"),
            (#"\bnewline\b[.,!?]?"#, "\n"),
            (#"\bline\s+break\b[.,!?]?"#, "\n"),
            (#"\b(?:new|next)\s+bullet(?:\s+point)?\b[.,!?]?"#, "\n- "),
            (#"\bbullet\s+point\b[.,!?]?"#, "\n- "),
        ]

        var text = input
        var changed = false
        for (pattern, template) in commands {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let next = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: template
            )
            if next != text {
                text = next
                changed = true
            }
        }
        guard changed else { return input }
        return normalizeLayout(text, capitalize: profile.capitalizesSentences)
    }

    /// Trims the gaps a replacement leaves behind and keeps paragraph breaks.
    /// Prose lines get a capital; code lines keep the speaker's casing.
    private static func normalizeLayout(_ input: String, capitalize: Bool) -> String {
        var text = replace(input, #"[ \t]*\r?\n[ \t]*"#, "\n")
        text = replace(text, #"\n{3,}"#, "\n\n")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let lines = text.components(separatedBy: "\n").map { line -> String in
            let collapsed = line.components(separatedBy: " ")
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard capitalize else { return collapsed }
            if collapsed.hasPrefix("- ") {
                return "- " + capitalizeFirst(String(collapsed.dropFirst(2)))
            }
            return capitalizeFirst(collapsed)
        }
        return lines.joined(separator: "\n")
    }

    private static func capitalizeFirst(_ input: String) -> String {
        guard let first = input.first, first.isLetter, first.isLowercase else { return input }
        return first.uppercased() + input.dropFirst()
    }

    // MARK: Tidy

    private static func tidy(_ input: String, endsPunctuated: Bool, profile: ContextProfile) -> String {
        var text = collapse(input)
        text = replace(text, #"\s+([,.;:!?])"#, "$1")
        text = replace(text, #"([、。])\s+"#, "$1")
        text = replace(text, #",\s*,"#, ",")
        text = replace(text, #"^[,;:\s]+"#, "")
        text = replace(text, #"\s+$"#, "")
        if profile.usesCodeSymbols {
            text = replace(text, #"\(\s+"#, "(")
            text = replace(text, #"\s+\)"#, ")")
            text = replace(text, #"\[\s+"#, "[")
            text = replace(text, #"\s+\]"#, "]")
            // Tidy removes the gap before "!" as punctuation; binary operators
            // need it back on both sides.
            text = replace(text, #"[ \t]*(===|!==|==|!=|=>|&&|\|\|)[ \t]*"#, " $1 ")
            text = replace(text, #"[ \t]{2,}"#, " ")
            text = text.trimmingCharacters(in: .whitespaces)
        }
        if profile.capitalizesSentences,
           let first = text.first, first.isLowercase {
            text = first.uppercased() + String(text.dropFirst())
        }
        if profile.addsTerminalPunctuation, endsPunctuated,
           let last = text.last, !".,!?…。".contains(last) {
            text += "."
        } else if !profile.addsTerminalPunctuation {
            // The recognizer punctuates everything; code and shell commands
            // should not end in a sentence period.
            text = replace(text, #"\s*\.$"#, "")
        }
        return text
    }

    /// The recognizer often writes a spoken "dash dash" as typographic dashes
    /// ("test – – watch"), and capitalizes the command ("NPM run"). Neither
    /// survives in a shell, so both are put back the way they are typed.
    private static let commandNames: Set<String> = [
        "npm", "npx", "pnpm", "yarn", "bun", "git", "brew", "pip", "python",
        "node", "docker", "kubectl", "cargo", "swift", "make", "cd", "ls",
    ]

    private static func commandFlags(_ input: String) -> String {
        var text = replace(input, #"(^|\s)[-–—]\s*[-–—]\s*([A-Za-z])"#, "$1--$2")
        text = replace(text, #"(^|\s)—\s*([A-Za-z])"#, "$1--$2")
        text = replace(text, #"(^|\s)–\s*([A-Za-z])"#, "$1-$2")
        if let first = text.split(separator: " ", maxSplits: 1).first,
           first != first.lowercased(),
           commandNames.contains(first.lowercased()) {
            text = first.lowercased() + text.dropFirst(first.count)
        }
        return text
    }

    // MARK: Helpers

    private static func collapse(_ input: String) -> String {
        input.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func words(_ input: String) -> [String] {
        input.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func replace(_ input: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        return regex.stringByReplacingMatches(in: input, range: NSRange(input.startIndex..., in: input), withTemplate: template)
    }

    /// Replacement text is inserted verbatim — no `$1` or backslash template
    /// rules, which matters when the symbol itself is a backslash.
    private static func replaceLiteral(_ input: String, _ pattern: String, _ literal: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        var out = ""
        var cursor = input.startIndex
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)) {
            guard let range = Range(match.range, in: input) else { continue }
            out += input[cursor..<range.lowerBound]
            out += literal
            cursor = range.upperBound
        }
        out += input[cursor...]
        return out
    }

    private static func replaceMapping(_ input: String, _ regex: NSRegularExpression,
                                       _ transform: ([String]) -> String) -> String {
        var out = ""
        var cursor = input.startIndex
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)) {
            guard let range = Range(match.range, in: input) else { continue }
            out += input[cursor..<range.lowerBound]
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                groups.append(Range(match.range(at: index), in: input).map { String(input[$0]) } ?? "")
            }
            out += transform(groups)
            cursor = range.upperBound
        }
        out += input[cursor...]
        return out
    }
}
