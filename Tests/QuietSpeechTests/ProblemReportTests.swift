import Foundation
import Testing
@testable import QuietSpeech

@Suite struct ProblemReportTests {
    @Test func payloadCarriesTheReportAndTrimsLongLogLines() throws {
        let long = String(repeating: "x", count: 2000)
        let report = ProblemReport(description: "  C++ & Rust broke\n", appName: " Xcode ", email: " me@example.com ",
                                   summary: ["QuietSpeech 1"], log: ["short", long])
        let payload = report.payload
        #expect(payload["description"] as? String == "C++ & Rust broke")
        #expect(payload["app"] as? String == "Xcode")
        #expect(payload["email"] as? String == "me@example.com")
        #expect(payload["summary"] as? [String] == ["QuietSpeech 1"])
        let log = try #require(payload["log"] as? [String])
        #expect(log.first == "short")
        #expect(log.last?.count == ProblemReport.maxLineLength)
        _ = try JSONSerialization.data(withJSONObject: payload)
    }

    @Test func replyAddressIsOptionalButChecked() {
        #expect(ProblemReport(description: "x", appName: "").isValidEmail)
        #expect(ProblemReport(description: "x", appName: "", email: "a@b.co").isValidEmail)
        #expect(!ProblemReport(description: "x", appName: "", email: "not an email").isValidEmail)
        #expect(!ProblemReport(description: "x", appName: "", email: "a@b").isValidEmail)
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
