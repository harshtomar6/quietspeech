import Foundation

/// Remembers where an inserted dictation sits in a text field by the text on
/// either side of it, so the same stretch can be found again after the user
/// has edited inside it. Offsets are UTF-16, like the Accessibility API's.
public struct InsertionAnchor: Equatable, Sendable {
    public let inserted: String
    let prefix: String
    let suffix: String
    let offset: Int

    static let contextLength = 40

    /// Finds `inserted` in the field's value. When it occurs more than once,
    /// the copy ending nearest the caret wins.
    public init?(inserted: String, in value: String, caret: Int?) {
        let field = value as NSString
        guard !inserted.isEmpty else { return nil }

        var best: NSRange?
        var searchRange = NSRange(location: 0, length: field.length)
        while true {
            let found = field.range(of: inserted, options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            if let caret, let current = best {
                if abs(NSMaxRange(found) - caret) < abs(NSMaxRange(current) - caret) { best = found }
            } else {
                best = found
            }
            let next = found.location + 1
            guard next < field.length else { break }
            searchRange = NSRange(location: next, length: field.length - next)
        }
        guard let range = best else { return nil }

        self.inserted = inserted
        self.offset = range.location
        self.prefix = Self.slice(field, from: range.location - Self.contextLength, to: range.location)
        self.suffix = Self.slice(field, from: NSMaxRange(range), to: NSMaxRange(range) + Self.contextLength)
    }

    /// The text now between the remembered neighbours, or nil when they're
    /// gone (the message was sent, the field cleared, or the edit reached
    /// past the dictation).
    public func span(in value: String) -> String? {
        let field = value as NSString

        var start = 0
        if !prefix.isEmpty {
            var best: NSRange?
            var searchRange = NSRange(location: 0, length: field.length)
            while true {
                let found = field.range(of: prefix, options: [], range: searchRange)
                guard found.location != NSNotFound else { break }
                if best == nil || abs(NSMaxRange(found) - offset) < abs(NSMaxRange(best!) - offset) { best = found }
                let next = found.location + 1
                guard next < field.length else { break }
                searchRange = NSRange(location: next, length: field.length - next)
            }
            guard let best else { return nil }
            start = NSMaxRange(best)
        }

        var end = field.length
        if !suffix.isEmpty {
            let found = field.range(of: suffix, options: [], range: NSRange(location: start, length: field.length - start))
            guard found.location != NSNotFound else { return nil }
            end = found.location
        }
        return field.substring(with: NSRange(location: start, length: end - start))
    }

    /// A substring that never splits a surrogate pair or composed character.
    private static func slice(_ string: NSString, from lower: Int, to upper: Int) -> String {
        let lower = max(0, lower), upper = min(string.length, upper)
        guard upper > lower else { return "" }
        let range = string.rangeOfComposedCharacterSequences(for: NSRange(location: lower, length: upper - lower))
        return string.substring(with: range)
    }
}

/// Counts how often corrections have been seen, so one stray edit never
/// changes anything. A term joins the vocabulary the second time it's typed
/// in as a fix, however it was misheard. A "heard → corrected" replacement
/// needs the same pair twice, because it rewrites text.
public struct CorrectionTally: Codable, Equatable, Sendable {
    public static let threshold = 2
    static let capacity = 200

    struct Entry: Codable, Equatable {
        var key: String
        var count: Int
    }

    /// Most recently seen last.
    private var entries: [Entry] = []

    public init() {}

    /// What a sighting makes ready to learn.
    public struct Outcome: Equatable, Sendable {
        public var terms: [String] = []
        public var replacement = false
    }

    /// Records a sighting. Whatever it makes ready is forgotten here, since
    /// it lives in the vocabulary from then on.
    public mutating func record(_ correction: Correction) -> Outcome {
        var outcome = Outcome()
        for term in correction.terms where bump("term\u{1F}" + term.lowercased()) {
            outcome.terms.append(term)
        }
        if correction.addsReplacement {
            outcome.replacement = bump("pair\u{1F}" + correction.heard.lowercased() + "\u{1F}" + correction.corrected)
        }
        return outcome
    }

    /// Counts one sighting of `key`; true when it reaches the threshold.
    private mutating func bump(_ key: String) -> Bool {
        var entry = Entry(key: key, count: 0)
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entry = entries.remove(at: index)
        }
        entry.count += 1
        guard entry.count < Self.threshold else { return true }
        entries.append(entry)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        return false
    }
}
