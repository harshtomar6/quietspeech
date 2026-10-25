import Foundation

/// One finished dictation, kept locally so it can be recovered after the
/// overlay has faded. Audio is never stored.
struct DictationRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var appName: String
    var text: String
    /// The uncleaned transcript, useful when a rule or replacement did
    /// something unexpected.
    var raw: String?
}
