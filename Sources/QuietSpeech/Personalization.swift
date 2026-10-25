import Foundation

/// A phrase that keeps getting misheard, mapped to how it should be written.
/// Applied deterministically after cleanup, so it can only swap words you
/// actually said — never invent new ones.
struct WordReplacement: Codable, Identifiable, Hashable {
    var id = UUID()
    var heard: String
    var replacement: String
    /// Added from the user's corrections. Optional so saved lists decode.
    var learned: Bool?

    var isUsable: Bool {
        !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
