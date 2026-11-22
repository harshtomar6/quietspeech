import Foundation
import Testing
@testable import QuietSpeech

@Suite struct ProblemReportTests {
    @Test func mailtoAddressesSupportAndKeepsSymbols() throws {
        let report = ProblemReport(description: "C++ & Rust = broken?\nsecond line", appName: "Xcode")
        let url = try #require(report.mailtoURL)
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "mailto")
        #expect(parts.path == ProblemReport.supportEmail)
        #expect(!(parts.percentEncodedQuery ?? "").contains("+"))
        let body = parts.queryItems?.first { $0.name == "body" }?.value
        #expect(body?.contains("C++ & Rust = broken?\nsecond line") == true)
        #expect(body?.contains("App I was typing into: Xcode") == true)
        let subject = parts.queryItems?.first { $0.name == "subject" }?.value
        #expect(subject?.hasSuffix(": C++ & Rust = broken?") == true)
    }

    @Test func noDiagnosticsWhenOff() {
        let report = ProblemReport(description: "x", appName: "")
        #expect(!report.body.contains("Diagnostics"))
        #expect(!report.body.contains("App I was typing into"))
    }

    @Test func longLogsDropOldestLines() {
        let log = (0..<2000).map { "line \($0) " + String(repeating: "x", count: 40) }
        let report = ProblemReport(description: "x", appName: "", summary: ["QuietSpeech 1"], log: log)
        let body = report.body
        #expect(body.count <= ProblemReport.maxBodyLength)
        #expect(body.contains("line 1999 "))
        #expect(!body.contains("line 0 "))
        #expect(body.contains("QuietSpeech 1"))
    }
}
