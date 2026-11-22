import AppKit
import Foundation
import OSLog

/// A problem report the user sends by email from Report a Problem.
///
/// Diagnostics describe the Mac and the app's decisions (versions, settings,
/// which insertion path ran). They never include audio or dictated text: the
/// app logs only counts and bundle IDs publicly, and anything logged as
/// private comes back from the log store redacted.
struct ProblemReport {
    static let supportEmail = "support@quietspeech.app"
    /// Mail clients and browser mail handlers accept long mailto URLs, but
    /// some stop around 64 KB. Logs are trimmed from the oldest end to fit.
    static let maxBodyLength = 24_000

    var description: String
    var appName: String
    /// Settings and system facts; empty when the user turned diagnostics off.
    var summary: [String] = []
    /// Recent log lines, oldest first; dropped from the oldest end to fit.
    var log: [String] = []

    var subject: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let firstLine = description
            .split(whereSeparator: \.isNewline).first
            .map { String($0.prefix(60)).trimmingCharacters(in: .whitespaces) } ?? ""
        return firstLine.isEmpty
            ? "QuietSpeech \(version): problem report"
            : "QuietSpeech \(version): \(firstLine)"
    }

    var body: String {
        var log = log[...]
        while true {
            let text = compose(log: Array(log))
            if text.count <= Self.maxBodyLength || log.isEmpty { return text }
            log = log.dropFirst(max(1, log.count / 10))
        }
    }

    /// The diagnostics exactly as they will be sent, for the preview.
    var diagnosticsText: String { Self.diagnostics(summary: summary, log: log) }

    private static func diagnostics(summary: [String], log: [String]) -> String {
        var text = summary.joined(separator: "\n")
        if !log.isEmpty { text += "\n\nRecent log:\n" + log.joined(separator: "\n") }
        return text
    }

    private func compose(log: [String]) -> String {
        var parts: [String] = []
        let what = description.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append("What happened:\n\(what.isEmpty ? "(not described)" : what)")
        let app = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !app.isEmpty { parts.append("App I was typing into: \(app)") }
        if !summary.isEmpty || !log.isEmpty {
            parts.append("--- Diagnostics (no audio or dictated text) ---\n"
                + Self.diagnostics(summary: summary, log: log))
        }
        return parts.joined(separator: "\n\n")
    }

    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        // URLComponents leaves "+" and "&" unescaped in query values;
        // mail clients read "+" as a space, so escape both.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}

enum Diagnostics {
    static let subsystem = "dev.harsh.quietspeech"

    /// Facts about this Mac and build.
    static func systemLines() -> [String] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let memoryGB = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        return [
            "QuietSpeech \(version) (build \(build))",
            "macOS \(os)",
            "Mac: \(sysctl("hw.model") ?? "unknown"), \(sysctl("machdep.cpu.brand_string") ?? "unknown chip"), \(memoryGB) GB",
        ]
    }

    /// The app's own log lines from the last `minutes`, newest last. Only
    /// this process's entries are readable, so this covers the time since
    /// QuietSpeech last started.
    static func recentLog(minutes: Double = 30, limit: Int = 150) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
            return ["(log unavailable)"]
        }
        let since = store.position(date: Date().addingTimeInterval(-minutes * 60))
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        guard let entries = try? store.getEntries(at: since, matching: predicate) else {
            return ["(log unavailable)"]
        }
        let time = DateFormatter()
        time.dateFormat = "HH:mm:ss.SSS"
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries {
            lines.append("\(time.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
        }
        return lines.suffix(limit).map { $0 }
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
